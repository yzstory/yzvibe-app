import fs from 'node:fs';
import { ompConfigRevision } from './omp-config.js';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { OmpRPC, ompChildPids } from './omp-rpc.js';
import { expandHome } from '../files.js';
import { accumulateUsage } from './usage.js';
import { importOmpImages } from './omp-transcripts.js';
import { ompCapabilities } from './omp-catalog.js';

const textOf = content => typeof content === 'string' ? content : (content ?? []).filter(x => x.type === 'text').map(x => x.text ?? '').join('\n');
const guard = fileURLToPath(new URL('./omp/guard.ts', import.meta.url));
export class OmpAgent {
  constructor({ session, store, internalURL, internalSecret, rpcFactory = options => new OmpRPC(options) }) {
    Object.assign(this, { session, store, internalURL, internalSecret, rpcFactory });
    this.rpc = null; this.active = null; this.requests = new Map(); this.disposed = false;
  }
  configure() { /* Applied before the next prompt; guard reads live mode for each tool. */ }
  async connect() {
    const revision = ompConfigRevision();
    if (this.rpc && !this.rpc.closed && this.configRevision === revision) return this.rpc;
    if (this.rpc) { const old = this.rpc; this.rpc = null; old.close(); }
    this.configRevision = revision;
    if (this.session.agentSessionId) await ensureNoTerminalWriter(expandHome(this.session.cwd));
    const args = ['--trusted-extension', guard];
    if (this.session.agentSessionId) args.push('--resume', this.session.agentSessionId);
    if (this.session.model) args.push('--model', this.session.model);
    const rpc = this.rpcFactory({ cwd: expandHome(this.session.cwd), args,
      env: { YZVIBE_OMP_PERMISSION_URL: this.internalURL, YZVIBE_OMP_SECRET: this.internalSecret, YZVIBE_OMP_SESSION: this.session.id } });
    this.rpc = rpc; this.guardReady = false;
    rpc.on('event', e => { if (this.rpc === rpc) this.event(e); });
    rpc.on('lateError', () => { if (this.rpc === rpc && this.active) this.fail(new Error('OMP 已接收请求，但随后调度失败；请检查历史后再发送')); });
    rpc.on('disconnect', e => { if (this.rpc === rpc) { this.rpc = null; if (this.active) this.fail(e); } });
    const ready = await rpc.ready;
    if (ready.supportedProtocolVersions?.includes(2)) await rpc.request('negotiate_protocol', { protocolVersion: 2 });
    const state = await rpc.request('get_state');
    if (!this.guardReady) { rpc.close(); throw new Error('OMP 权限扩展未就绪，已阻止发送'); }
    if (!state.sessionId) throw new Error('OMP 未返回会话 ID');
    this.store.setAgentSessionId(this.session.id, state.sessionId);
    this.defaultModel = state.model; this.defaultEffort = state.thinkingLevel;
    const commands = await rpc.request('get_available_commands'); this.catalog(commands.commands ?? []);
    return rpc;
  }
  async send(text, attachments = []) {
    if (this.disposed || this.active) throw new Error('OMP 会话不可用或正在运行');
    const active = { prefix: randomUUID(), messages: new Set(), done: new Set(), usage: [], started: Date.now(), stopped: false };
    this.active = active; this.store.setStatus(this.session.id, 'running');
    try {
      const rpc = await this.connect();
      if (this.active !== active || active.stopped) throw new Error('发送已取消');
      const caps = await ompCapabilities();
      const defaultId = this.defaultModel && `${this.defaultModel.provider}/${this.defaultModel.id}`;
      const model = this.session.model ?? (caps.models.some(m => m.id === defaultId) ? defaultId : caps.models[0]?.id);
      if (!model || !caps.models.some(m => m.id === model)) throw new Error('请先配置 OMP 模型，或重新选择电脑端已配置的模型');
      if (model) { const split = model.indexOf('/'); if (split < 1) throw new Error('OMP 模型必须包含供应商 ID'); await rpc.request('set_model', { provider: model.slice(0, split), modelId: model.slice(split + 1) }); }
      const option = caps.models.find(m => m.id === model);
      if (this.session.effort && !['off', 'auto', ...(option?.efforts ?? [])].includes(this.session.effort)) throw new Error('该 OMP 模型不支持所选思考力度');
      await rpc.request('set_thinking_level', { level: this.session.effort ?? this.defaultEffort ?? 'off' });
      const images = [];
      let message = text ?? '';
      // Native slash commands can bypass tool interception. Route only the explicitly supported safe subset.
      if (message.trimStart().startsWith('/') && !/^\/(compact|context|usage|help|skill:[^\s]+)(\s|$)/.test(message.trimStart())) throw new Error('此 OMP 命令需要在电脑终端执行；手机支持 /compact、/context、/usage 和技能');
      for (const id of attachments) {
        const upload = this.store.upload(id); if (!upload) throw new Error('附件已失效');
        if (upload.mime.startsWith('image/')) {
          if (!option?.imageInput) throw new Error('当前 OMP 模型不支持图片，请切换支持图片的模型');
          images.push({ type: 'image', data: fs.readFileSync(upload.path).toString('base64'), mimeType: upload.mime });
        } else message += `\n用户附带文件（按需读取）：${JSON.stringify({ name: upload.name, path: upload.path })}`;
      }
      if (this.session.mode === 'plan' && !message.trimStart().startsWith('/')) message = '只分析并给出计划，不修改文件；工具层仅允许本地读取和搜索。\n\n' + message;
      // OMP inbound frames are capped. Check before sending so unsupported images never silently disappear.
      if (Buffer.byteLength(JSON.stringify({ message, images })) > 1_000_000) throw new Error('OMP 单次输入上限约 1 MB，请减少图片大小或数量');
      await rpc.request('set_session_name', { name: this.session.title || 'OMP 会话' });
      const result = await rpc.request('prompt', { message: message || '请查看附件。', images });
      if (result.agentInvoked === false && this.active === active) await this.finish('completed');
    } catch (e) { this.fail(e); throw e; }
  }
  catalog(commands) {
    this.store.setSessionCatalog(this.session.id, { slashCommands: commands.map(c => c.name), skills: commands.filter(c => c.source === 'skill').map(c => c.name) });
  }
  messageId() {
    if (!this.active.messageId) { this.active.messageId = `${this.active.prefix}-${this.active.messages.size}`; this.active.messages.add(this.active.messageId); }
    return this.active.messageId;
  }
  event(e) {
    if (e.type === 'extension_ui_request' && e.method === 'notify' && e.message === 'yzvibe-omp-guard-ready-v1') { this.guardReady = true; return; }
    if (e.type === 'extension_error') { this.fail(new Error('OMP 扩展加载或执行失败，已停止本轮')); return; }
    if (e.type === 'available_commands_update') { this.catalog(e.commands ?? []); return; }
    if (e.type === 'extension_ui_request') { void this.dialog(e).catch(() => this.fail(new Error('OMP 提问处理失败'))); return; }
    const a = this.active; if (!a) return;
    if (e.type === 'message_start' && e.message?.role === 'assistant') { a.messageId = null; this.messageId(); }
    if (e.type === 'message_update' && e.assistantMessageEvent?.type === 'text_delta') this.store.appendDelta(this.session.id, this.messageId(), e.assistantMessageEvent.delta);
    if (e.type === 'message_end' && e.message?.role === 'assistant') {
      const id = this.messageId();
      if (!a.done.has(id)) {
        a.done.add(id); this.store.ensureAssistantMessage(this.session.id, id);
        this.store.finishMessage(this.session.id, id, textOf(e.message.content));
        const images = importOmpImages(e.message.content, (...args) => this.store.addUpload(...args));
        if (images.length) this.store.addMessage(this.session.id, { role: 'assistant', text: '', attachments: images });
        if (e.message.usage) a.usage.push(e.message.usage);
        if (e.message.stopReason === 'error') a.error = e.message.errorMessage || '模型请求失败';
      }
    }
    if (e.type.startsWith('tool_execution_')) {
      const result = e.result ?? e.partialResult;
      if (e.type === 'tool_execution_end') {
        const images = importOmpImages(result?.content, (...args) => this.store.addUpload(...args));
        if (images.length) this.store.addMessage(this.session.id, { role: 'assistant', text: '', attachments: images });
      }
      this.store.upsertToolCall(this.session.id, { id: `${a.prefix}-${e.toolCallId}`, name: e.toolName ?? 'Tool',
        ...(e.args && { input: e.args, detail: JSON.stringify(e.args) }),
        state: e.type === 'tool_execution_end' ? e.isError ? 'error' : 'done' : 'running',
        ...(result && { output: textOf(result.content).slice(0, 64_000), truncated: textOf(result.content).length > 64_000, exitCode: result.details?.exitCode }) }, this.messageId());
    }
    if (e.type === 'command_output') this.store.appendDelta(this.session.id, this.messageId(), typeof e.text === 'string' ? e.text : typeof e.output === 'string' ? e.output : textOf(e.content));
    if (e.type === 'prompt_result' && e.agentInvoked === false) void this.finish('completed');
    if (e.type === 'agent_end' && e.isTerminal !== false) void this.finish(a.error ? 'failed' : a.stopped ? 'interrupted' : 'completed');
  }
  async dialog(e) {
    const rpc = this.rpc;
    if (e.method === 'cancel') { this.requests.get(e.id)?.abort(); return; }
    if (!['confirm', 'select', 'input', 'editor'].includes(e.method)) return;
    const controller = new AbortController(); this.requests.set(e.id, controller);
    try {
      const questions = [{ id: 'answer', question: e.message || e.title || 'OMP 提问', options: (e.method === 'confirm' ? ['是', '否'] : e.options ?? []).map(label => ({ label, description: '' })) }];
      const result = await this.store.requestApproval({ sessionId: this.session.id, agent: 'omp', toolName: 'Ask', kind: 'other', summary: e.title || 'OMP 提问', detail: e.message || '', risk: 'low', questions, allowRules: false, signal: controller.signal });
      const answer = result?.answers?.answer;
      if (e.method === 'confirm') rpc?.write({ type: 'extension_ui_response', id: e.id, confirmed: !!answer && !/^(否|不|no|cancel)/i.test(answer) });
      else rpc?.write({ type: 'extension_ui_response', id: e.id, ...(answer ? { value: answer } : { cancelled: true }) });
    } catch (error) {
      if (!controller.signal.aborted) throw error;
      if (rpc && !rpc.closed) rpc.write({ type: 'extension_ui_response', id: e.id, cancelled: true });
    } finally { this.requests.delete(e.id); }
  }
  async finish(status) {
    const a = this.active; if (!a || a.finishing) return; a.finishing = true;
    try {
      const state = await this.rpc?.request('get_state');
      if (this.active !== a) return;
      const sum = key => a.usage.reduce((n, u) => n + (Number(u[key]) || 0), 0);
      this.store.setUsage(this.session.id, accumulateUsage(this.session.usage, {
        model: state?.model ? `${state.model.provider}/${state.model.id}` : this.session.model,
        input: sum('input'), output: sum('output'), cacheRead: sum('cacheRead'), cacheWrite: sum('cacheWrite'), thinking: sum('reasoningTokens'),
        contextTokens: state?.contextUsage?.tokens ?? null, contextWindow: state?.contextUsage?.contextWindow ?? null,
        costUSD: null, durationMs: Date.now() - a.started,
      }));
    } catch { /* Completion remains valid even if the final usage query fails. */ }
    if (this.active !== a) return;
    this.active = null; clearTimeout(a.stopTimer);
    for (const id of a.messages) if (!a.done.has(id)) this.store.finishMessage(this.session.id, id);
    for (const c of this.requests.values()) c.abort(); this.requests.clear();
    if (a.error) this.store.addMessage(this.session.id, { role: 'system', text: `OMP：${a.error}` });
    if (status !== 'completed' && !(status === 'interrupted' && a.resumeQueue)) this.store.pauseQueue(this.session.id);
    this.store.setStatus(this.session.id, status === 'failed' ? 'error' : 'idle');
  }
  stop({ resumeQueue = false } = {}) {
    const a = this.active; if (!a) return; a.stopped = true; a.resumeQueue = resumeQueue;
    for (const c of this.requests.values()) c.abort();
    void this.rpc?.request('abort').catch(() => this.fail(new Error('OMP 中断失败')));
    a.stopTimer = setTimeout(() => this.fail(new Error('OMP 未确认停止，队列已保留')), 10_000); a.stopTimer.unref?.();
  }
  fail(error) {
    const a = this.active;
    if (a) {
      this.active = null; clearTimeout(a.stopTimer);
      for (const id of a.messages) {
        for (const tool of this.store.messagesOf(this.session.id).find(m => m.id === id)?.toolCalls ?? []) {
          if (tool.state === 'running') this.store.upsertToolCall(this.session.id, { ...tool, state: 'error', output: 'OMP 连接中断，执行结果待确认' }, id);
        }
        this.store.finishMessage(this.session.id, id);
      }
      this.store.pauseQueue(this.session.id);
      this.store.addMessage(this.session.id, { role: 'system', text: `OMP：${error.message}` });
      this.store.setStatus(this.session.id, 'error');
    }
    for (const c of this.requests.values()) c.abort(); this.requests.clear();
    const rpc = this.rpc; this.rpc = null; rpc?.close();
  }
  dispose() { this.disposed = true; this.fail(new Error('会话已关闭')); }
}

// Native OMP does not coordinate two writers. Conservatively block a resume while a
// standalone OMP terminal is open in this directory; our own RPC children are excluded.
async function ensureNoTerminalWriter(cwd) {
  const run = promisify(execFile);
  const { stdout } = await run('ps', ['-axo', 'pid=,comm='], { timeout: 4000, maxBuffer: 1024 * 1024 });
  for (const line of stdout.split('\n')) {
    const match = line.trim().match(/^(\d+)\s+(.+)$/);
    if (!match || !/^omp(?:\s|$)/.test(path.basename(match[2])) || ompChildPids.has(Number(match[1]))) continue;
    let listing;
    try { listing = await run('lsof', ['-a', '-p', match[1], '-d', 'cwd', '-Fn'], { timeout: 4000, maxBuffer: 16384 }); }
    catch { throw new Error('无法确认电脑端 OMP 是否正在使用此会话，请先退出终端 OMP 后重试'); }
    const directory = listing.stdout.split('\n').find(l => l.startsWith('n'))?.slice(1);
    if (!directory || fs.realpathSync(directory) === fs.realpathSync(cwd)) throw new Error('此目录已有终端 OMP 正在使用，请先退出终端会话，再从手机继续');
  }
}
