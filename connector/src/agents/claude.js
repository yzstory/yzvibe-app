// Claude Code 驱动：claude -p --input-format stream-json --output-format stream-json
// 权限提示通过 --permission-prompt-tool 走 MCP（src/mcp-approve.js），由手机审批。
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { expandHome } from '../files.js';
import { claudeOptionArgs } from './options.js';
import { claudeTurnUsage, accumulateUsage } from './usage.js';
import { rememberRateLimit } from '../quota.js';

export class ClaudeAgent {
  constructor({ session, store, internalURL, internalSecret, home, options = {} }) {
    Object.assign(this, { session, store, internalURL, internalSecret, home, options });
    this.proc = null;
    this.buffer = '';
    this.currentMessageId = null;
    this.currentText = '';
    this.sawDelta = false;
    this.needsRespawn = false;
    this.modelId = null;            // system.init 里的模型
    this.lastMessageUsage = null;   // 最后一条 assistant 消息的 usage，用于算上下文大小
  }

  /** 手机切换了 mode / model / effort：这些是 claude 进程级参数，空闲时在下一轮以 --resume 重启进程生效。 */
  configure() { this.needsRespawn = true; }

  #mcpConfigPath() {
    const file = path.join(this.home, `mcp-${this.session.id}.json`);
    const config = {
      mcpServers: {
        yzvibe: {
          command: process.execPath,
          args: [path.join(path.dirname(new URL(import.meta.url).pathname), '..', 'mcp-approve.js')],
          env: { YZVIBE_INTERNAL: this.internalURL, YZVIBE_SECRET: this.internalSecret, YZVIBE_SESSION: this.session.id },
        },
      },
    };
    fs.writeFileSync(file, JSON.stringify(config));
    return file;
  }

  #spawn() {
    const { session, options } = this;
    const args = ['-p', '--verbose', '--input-format', 'stream-json', '--output-format', 'stream-json', '--include-partial-messages',
                  '--mcp-config', this.#mcpConfigPath(),
                  ...claudeOptionArgs({ mode: session.mode, model: session.model, effort: session.effort })];
    if (session.agentSessionId) args.push('--resume', session.agentSessionId);
    else if (options.continueLast) args.push('--continue');
    this.needsRespawn = false;

    const cwd = expandHome(session.cwd);
    this.proc = spawn('claude', args, { cwd, stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env, CLAUDECODE: undefined } });
    this.proc.stdout.on('data', (b) => this.#onData(b));
    this.proc.stderr.on('data', (b) => { const s = String(b).trim(); if (s) console.error(`[claude ${session.id.slice(0, 8)}] ${s}`); });
    this.proc.on('exit', (code) => {
      this.proc = null;
      if (this.currentMessageId) this.store.finishMessage(session.id, this.currentMessageId, this.currentText || undefined);
      this.currentMessageId = null;
      this.store.setStatus(session.id, code === 0 || code === null ? 'idle' : 'error');
    });
    this.proc.on('error', (e) => {
      this.store.addMessage(session.id, { role: 'system', text: `无法启动 claude：${e.message}` });
      this.store.setStatus(session.id, 'error');
    });
  }

  /** 丢弃旧进程（不再触发它的 exit 状态回写），下一次 spawn 用 --resume 接上同一段对话。 */
  #retire() {
    const p = this.proc; if (!p) return;
    this.proc = null;
    p.removeAllListeners('exit'); p.on('exit', () => {});
    try { p.stdin.end(); } catch {}
    p.kill('SIGTERM');
  }

  async send(text, attachments = []) {
    if (this.proc && this.needsRespawn && this.session.status !== 'running' && this.session.status !== 'waiting_approval') this.#retire();
    if (!this.proc) this.#spawn();
    const content = text?.trim() ? [{ type: 'text', text }] : [];   // 空文本块会被 API 拒绝，只发图时省略
    for (const a of attachments) {
      const up = this.store.upload(a);
      if (up && up.mime.startsWith('image/')) content.push({ type: 'image', source: { type: 'base64', media_type: up.mime, data: fs.readFileSync(up.path).toString('base64') } });
    }
    this.store.setStatus(this.session.id, 'running');
    this.proc.stdin.write(JSON.stringify({ type: 'user', message: { role: 'user', content } }) + '\n');
  }

  stop() {
    if (this.proc) { this.proc.kill('SIGINT'); }
  }

  dispose() { this.stop(); try { fs.unlinkSync(path.join(this.home, `mcp-${this.session.id}.json`)); } catch {} }

  #onData(buf) {
    this.buffer += String(buf);
    let i;
    while ((i = this.buffer.indexOf('\n')) >= 0) {
      const line = this.buffer.slice(0, i).trim();
      this.buffer = this.buffer.slice(i + 1);
      if (!line) continue;
      let ev; try { ev = JSON.parse(line); } catch { continue; }
      this.#handle(ev);
    }
  }

  #ensureMessage() {
    if (!this.currentMessageId) { this.currentMessageId = randomUUID(); this.currentText = ''; this.sawDelta = false; }
    return this.currentMessageId;
  }

  #handle(ev) {
    const { store, session } = this;
    switch (ev.type) {
      case 'system':
        if (ev.subtype === 'init') { if (ev.session_id) store.setAgentSessionId(session.id, ev.session_id); if (ev.model) this.modelId = ev.model; }
        break;
      case 'rate_limit_event':
        rememberRateLimit(ev.rate_limit_info);
        break;
      case 'stream_event': {
        const e = ev.event;
        if (e?.type === 'content_block_delta' && e.delta?.type === 'text_delta') {
          const mid = this.#ensureMessage();
          this.sawDelta = true;
          this.currentText += e.delta.text;
          store.appendDelta(session.id, mid, e.delta.text);
        }
        break;
      }
      case 'assistant': {
        if (ev.message?.usage) this.lastMessageUsage = ev.message.usage;
        const blocks = ev.message?.content ?? [];
        const text = blocks.filter((b) => b.type === 'text').map((b) => b.text).join('');
        const mid = this.#ensureMessage();
        if (text && !this.sawDelta) { this.currentText += text; store.appendDelta(session.id, mid, text); }
        for (const b of blocks.filter((b) => b.type === 'tool_use')) {
          store.upsertToolCall(session.id, { id: b.id, name: b.name, detail: summarizeInput(b.name, b.input), state: 'running' });
        }
        break;
      }
      case 'user': {
        for (const b of ev.message?.content ?? []) {
          if (b.type === 'tool_result') {
            store.upsertToolCall(session.id, { id: b.tool_use_id, state: b.is_error ? 'error' : 'done' });
          }
        }
        // 工具结果之后 Claude 会继续输出新一段文本，开启新消息
        if (this.currentMessageId) { store.finishMessage(session.id, this.currentMessageId, this.currentText || undefined); this.currentMessageId = null; }
        break;
      }
      case 'result': {
        if (this.currentMessageId) { store.finishMessage(session.id, this.currentMessageId, this.currentText || undefined); this.currentMessageId = null; }
        if (ev.session_id) store.setAgentSessionId(session.id, ev.session_id);
        if (ev.is_error) store.addMessage(session.id, { role: 'system', text: `Claude 出错：${ev.result ?? ev.subtype}` });
        if (ev.usage) store.setUsage(session.id, accumulateUsage(session.usage, claudeTurnUsage(ev, this.lastMessageUsage, this.modelId)));
        store.setStatus(session.id, ev.is_error ? 'error' : 'idle');
        break;
      }
      default: break;
    }
  }
}

export function summarizeInput(name, input = {}) {
  if (typeof input.command === 'string') return input.command;
  if (typeof input.file_path === 'string') return input.file_path;
  if (typeof input.pattern === 'string') return input.pattern;
  if (typeof input.url === 'string') return input.url;
  if (typeof input.query === 'string') return input.query;
  const s = JSON.stringify(input); return s.length > 120 ? s.slice(0, 117) + '…' : s;
}

/** 把权限请求映射为审批卡字段。 */
export function classifyPermission(toolName, input = {}) {
  const summary = summarizeInput(toolName, input);
  if (toolName === 'Bash' || toolName === 'PowerShell') {
    const cmd = String(input.command ?? '');
    const high = /\brm\s+-rf\b|\bsudo\b|--force\b|\bgit\s+push\b|\bcurl\b.*\|\s*(ba)?sh|\bdd\b|\bmkfs\b|\bchmod\s+-R\b|\bkill\b|\bdocker\s+(rm|system\s+prune)\b/.test(cmd);
    return { kind: 'shell', risk: high ? 'high' : 'medium', summary, detail: cmd || summary };
  }
  if (/^(Write|Edit|MultiEdit|NotebookEdit)$/.test(toolName)) {
    const outside = typeof input.file_path === 'string' && (input.file_path.startsWith('/etc') || input.file_path.startsWith('/usr') || input.file_path.includes('/.ssh/'));
    return { kind: 'write', risk: outside ? 'high' : 'low', summary, detail: `${toolName} ${summary}` };
  }
  if (/^(WebFetch|WebSearch)$/.test(toolName)) return { kind: 'network', risk: 'low', summary, detail: `${toolName} ${summary}` };
  if (toolName === 'ExitPlanMode') {
    const plan = typeof input.plan === 'string' ? input.plan : '';
    return { kind: 'other', risk: 'low', summary: '批准计划，开始执行', detail: plan ? plan.slice(0, 4000) : 'Claude 已完成规划，批准后切换到 Normal 模式开始改动。' };
  }
  return { kind: 'other', risk: 'medium', summary: `${toolName}: ${summary}`, detail: JSON.stringify(input, null, 2).slice(0, 2000) };
}
