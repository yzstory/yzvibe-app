// Codex CLI 驱动：每一轮对话起一个 `codex exec --json`（续聊用 `codex exec resume <thread>`）。
// 选项（mode / model / effort）是进程级参数，所以手机上切换后下一轮自动生效，无需重启常驻进程。
// Codex 非交互模式没有审批回调：normal 靠 workspace-write 沙箱兜底，沙箱外操作被直接拒绝。
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { expandHome } from '../files.js';
import { codexOptionArgs, CODEX_PLAN_PREFIX, codexContextWindow } from './options.js';
import { codexTurnUsage, accumulateUsage } from './usage.js';

export class CodexAgent {
  constructor({ session, store, spawnProcess = spawn }) {
    Object.assign(this, { session, store, spawnProcess });
    this.proc = null;
    this.buffer = '';
    this.queue = [];
    this.turnErrored = false;
    this.contextWindow = null;
    codexContextWindow(session.model).then((w) => { this.contextWindow = w; }).catch(() => {});
  }

  configure() { /* 每轮重新拼参数，无需处理 */ }

  async send(text, attachments = []) {
    if (this.proc) { this.queue.push({ text, attachments }); return; }
    this.#spawn(text, attachments);
  }

  stop() {
    const p = this.proc; if (!p) return;
    this.queue = [];
    p.kill('SIGTERM');
    setTimeout(() => { try { p.kill('SIGKILL'); } catch {} }, 2000).unref();
  }

  dispose() { this.stop(); }

  #spawn(text, attachments) {
    const { session, store } = this;
    const opts = { mode: session.mode, model: session.model, effort: session.effort };
    let prompt = (opts.mode === 'plan' ? CODEX_PLAN_PREFIX : '') + (text?.trim() ? text : (attachments.length ? '请看附带的图片。' : text));
    const args = session.agentSessionId ? ['exec', 'resume', ...codexOptionArgs(opts)] : ['exec', ...codexOptionArgs(opts)];
    for (const a of attachments) {
      const up = store.upload(a);
      if (up && up.mime.startsWith('image/')) args.push('-i', up.path);
      else if (up) prompt += `\n用户附带文件（请根据需要读取）：${JSON.stringify({ name: up.name, path: up.path })}`;
    }
    // --image is variadic on new exec: terminate options before positional args.
    // Pipe the prompt so images cannot swallow it and long messages avoid argv limits.
    args.push('--');
    if (session.agentSessionId) args.push(session.agentSessionId);
    args.push('-');

    this.turnErrored = false;
    store.setStatus(session.id, 'running');
    this.proc = this.spawnProcess('codex', args, { cwd: expandHome(session.cwd), stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env } });
    let stderr = '';
    this.proc.stdin.on('error', (error) => { if (error.code !== 'EPIPE') console.error(`[codex stdin] ${error.message}`); });
    this.proc.stdout.on('data', (b) => this.#onData(b));
    this.proc.stderr.on('data', (b) => { const s = String(b).trim(); stderr = (stderr + String(b)).slice(-4000); if (s && !/^(Reading additional input|Shell cwd was reset)/.test(s)) console.error(`[codex ${session.id.slice(0, 8)}] ${s}`); });
    this.proc.on('close', (code) => {
      this.proc = null;
      if (this.buffer.trim()) { this.#handleLine(this.buffer); this.buffer = ''; }
      if (code && code !== 0 && !this.turnErrored) store.addMessage(session.id, { role: 'system', text: `Codex 退出，代码 ${code}${stderr.trim() ? `：${humanError(stderr.trim())}` : ''}` });
      store.setStatus(session.id, !this.turnErrored && (code === 0 || code === null) ? 'idle' : 'error');
      const next = this.queue.shift();
      if (next) this.#spawn(next.text, next.attachments);
    });
    this.proc.on('error', (e) => {
      store.addMessage(session.id, { role: 'system', text: `无法启动 codex：${e.message}` });
      store.setStatus(session.id, 'error');
      this.proc = null;
      this.turnErrored = true;
    });
    this.proc.stdin.end(prompt ?? '');
  }

  #onData(buf) {
    this.buffer += String(buf);
    let i;
    while ((i = this.buffer.indexOf('\n')) >= 0) {
      const line = this.buffer.slice(0, i).trim();
      this.buffer = this.buffer.slice(i + 1);
      if (line) this.#handleLine(line);
    }
  }

  #handleLine(line) {
    let ev; try { ev = JSON.parse(line); } catch { return; }
    handleCodexEvent(ev, this.store, this.session, this);
  }
}

/** 把 `codex exec --json` 的一行事件写进 store（导出便于测试）。
 *  Codex 的 item id 每轮从 item_0 重新计数，这里加上轮次前缀避免跨轮撞到同一条消息 / 工具卡。 */
export function handleCodexEvent(ev, store, session, state = {}) {
  switch (ev.type) {
    case 'thread.started':
      if (ev.thread_id) store.setAgentSessionId(session.id, ev.thread_id);
      break;
    case 'turn.started':
      state.turn = randomUUID().slice(0, 8);
      break;
    case 'item.started':
    case 'item.completed': {
      const raw = ev.item ?? {};
      const it = { ...raw, id: `${state.turn ?? (state.turn = randomUUID().slice(0, 8))}-${raw.id ?? randomUUID()}` };
      const done = ev.type === 'item.completed';
      switch (it.type) {
        case 'agent_message':
          if (done && it.text) { store.appendDelta(session.id, it.id, it.text); store.finishMessage(session.id, it.id); }
          break;
        case 'command_execution': {
          const out = done ? String(it.aggregated_output ?? it.output ?? '').trim() : '';
          store.upsertToolCall(session.id, { id: it.id, name: 'Shell', detail: stripShell(it.command),
            state: !done ? 'running' : it.exit_code === 0 || it.status === 'completed' ? 'done' : 'error',
            ...(out ? { output: out, outputKind: 'text' } : {}) }, toolBubble(state));
          break;
        }
        case 'file_change': {
          const changes = it.changes ?? [];
          const paths = changes.map((c) => c.path).filter(Boolean);
          const diff = changes.map((c) => c.diff ?? c.unified_diff).filter(Boolean).join('\n');
          store.upsertToolCall(session.id, { id: it.id, name: 'Edit', detail: paths.join(', ') || '文件改动',
            state: done ? (it.status === 'failed' ? 'error' : 'done') : 'running',
            ...(diff ? { output: diff, outputKind: 'diff' } : paths.length ? { output: paths.map((x) => `~ ${x}`).join('\n'), outputKind: 'text' } : {}) }, toolBubble(state));
          break;
        }
        case 'mcp_tool_call': {
          const res = done ? String(it.result?.content ?? it.result ?? '').trim() : '';
          store.upsertToolCall(session.id, { id: it.id, name: `${it.server ?? 'mcp'}.${it.tool ?? ''}`, detail: JSON.stringify(it.arguments ?? {}).slice(0, 120),
            state: done ? (it.status === 'failed' ? 'error' : 'done') : 'running', ...(res && res !== '[object Object]' ? { output: res, outputKind: 'text' } : {}) }, toolBubble(state));
          break;
        }
        case 'web_search':
          store.upsertToolCall(session.id, { id: it.id, name: 'WebSearch', detail: it.query ?? '', state: done ? 'done' : 'running' }, toolBubble(state));
          break;
        case 'error':
          console.error(`[codex ${session.id.slice(0, 8)}] ${it.message}`);
          break;
        default: break;   // reasoning / todo_list 等不上屏
      }
      break;
    }
    case 'error':
      state.turnErrored = true;
      store.addMessage(session.id, { role: 'system', text: `Codex 出错：${humanError(ev.message)}` });
      break;
    case 'turn.completed':
      if (ev.usage) store.setUsage(session.id, accumulateUsage(session.usage, codexTurnUsage(ev.usage, session.model, state.contextWindow ?? null)));
      break;
    case 'turn.failed':
      if (!state.turnErrored) { state.turnErrored = true; store.addMessage(session.id, { role: 'system', text: `Codex 出错：${humanError(ev.error?.message)}` }); }
      break;
    default: break;
  }
}

/** 同一轮的工具卡放进同一个助手气泡（Codex 的 item 不属于任何消息）。 */
function toolBubble(state) { return `${state.turn ?? 'turn'}-tools`; }

function stripShell(cmd = '') {
  const m = String(cmd).match(/^\/bin\/(?:ba|z)?sh -lc '([\s\S]*)'$/);
  return m ? m[1] : String(cmd);
}

function humanError(msg = '') {
  try { const j = JSON.parse(msg); return j.error?.message ?? j.message ?? msg; } catch { return msg || '未知错误'; }
}
