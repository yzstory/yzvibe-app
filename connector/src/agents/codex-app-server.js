import { randomUUID } from 'node:crypto';
import { expandHome } from '../files.js';
import { CodexRPC } from './codex-rpc.js';
import { CODEX_PLAN_PREFIX } from './options.js';
import { classifyPermission } from './claude.js';
import { accumulateUsage } from './usage.js';

export function appServerOptions(session) {
  const plan = session.mode === 'plan', trust = session.mode === 'trust';
  return {
    approvalPolicy: trust || plan ? 'never' : 'on-request',
    sandbox: trust ? 'danger-full-access' : plan ? 'read-only' : 'workspace-write',
    sandboxPolicy: trust ? { type: 'dangerFullAccess' } : plan ? { type: 'readOnly' }
      : { type: 'workspaceWrite', writableRoots: [expandHome(session.cwd)], networkAccess: false },
  };
}

/** Private App Server per turn. Resume the original thread; Store is the single queue owner. */
export class CodexAgent {
  constructor({ session, store, spawnProcess, rpcFactory, interruptTimeout = 10_000 }) {
    Object.assign(this, { session, store, interruptTimeout });
    this.rpcFactory = rpcFactory ?? (options => new CodexRPC({ ...options, spawnProcess }));
    this.rpc = null; this.active = null; this.disposed = false;
  }
  configure() { /* Explicit overrides on the next turn, never restart an active turn. */ }

  async connect() {
    if (this.rpc && !this.rpc.closed) return this.rpc;
    const rpc = this.rpcFactory({ cwd: expandHome(this.session.cwd) });
    this.rpc = rpc;
    rpc.on('notification', event => { if (this.rpc === rpc) this.notification(event); });
    rpc.on('request', event => { void this.serverRequest(rpc, event).catch(error => this.fail(error)); });
    rpc.on('disconnect', error => {
      if (this.rpc !== rpc) return;
      this.rpc = null;
      if (this.active) this.fail(error);
    });
    await rpc.request('initialize', { clientInfo: { name: 'yzvibe', title: 'YzVibe', version: '0.1.0' } });
    rpc.notify('initialized', {});
    const opts = appServerOptions(this.session);
    const params = { cwd: expandHome(this.session.cwd), model: this.session.model ?? null,
      approvalPolicy: opts.approvalPolicy, sandbox: opts.sandbox,
      approvalsReviewer: 'user', ...(this.session.effort ? { config: { model_reasoning_effort: this.session.effort } } : {}) };
    const result = this.session.agentSessionId
      ? await rpc.request('thread/resume', { ...params, threadId: this.session.agentSessionId, excludeTurns: true })
      : await rpc.request('thread/start', params);
    if (!result.thread?.id) throw new Error('Codex 未返回会话 ID');
    this.store.setAgentSessionId(this.session.id, result.thread.id);
    this.defaultModel = result.model;
    this.defaultEffort = result.reasoningEffort;
    return rpc;
  }

  async send(text, attachments = []) {
    if (this.disposed) throw new Error('会话已关闭');
    if (this.active) throw new Error('Codex 正忙，请使用会话队列');
    const active = { id: null, prefix: randomUUID(), items: new Map(), requests: new Map(),
      completed: new Set(), streams: new Set(), totals: null, usage: null, previousUsage: this.session.usage,
      stopped: false, interruptSent: false, startedAt: Date.now() };
    this.active = active;
    this.store.setStatus(this.session.id, 'running');
    try {
      const rpc = await this.connect();
      if (this.active !== active || active.stopped) throw new Error('发送已取消');
      const input = [];
      for (const id of attachments) {
        const upload = this.store.upload(id);
        if (!upload?.mime?.startsWith('image/')) throw new Error('附带的图片已失效，请重新选择');
        input.push({ type: 'localImage', path: upload.path });
      }
      input.unshift({ type: 'text', text: (this.session.mode === 'plan' ? CODEX_PLAN_PREFIX : '')
        + (text?.trim() ? text : attachments.length ? '请看附带的图片。' : '') });
      const opts = appServerOptions(this.session);
      const result = await rpc.request('turn/start', { threadId: this.session.agentSessionId, input,
        cwd: expandHome(this.session.cwd), approvalPolicy: opts.approvalPolicy, approvalsReviewer: 'user',
        sandboxPolicy: opts.sandboxPolicy, model: this.session.model ?? this.defaultModel,
        effort: this.session.effort ?? this.defaultEffort });
      if (this.active === active) {
        active.id = result.turn.id;
        active.delivered = true;
        if (active.stopped) this.interrupt(active);
      }
    } catch (error) {
      if (active.finished && active.delivered) return; // A turn event also proves delivery if the response was lost.
      this.fail(error);
      throw error; // An uncertain turn/start is never automatically replayed.
    }
  }

  stop() {
    if (!this.active) return;
    this.active.stopped = true;
    this.cancelRequests(this.active);
    this.interrupt(this.active);
  }
  interrupt(active) {
    if (!active.id || active.interruptSent || this.active !== active) return;
    active.interruptSent = true;
    void this.rpc.request('turn/interrupt', { threadId: this.session.agentSessionId, turnId: active.id }, this.interruptTimeout)
      .catch(error => { if (this.active === active) this.fail(error); });
    active.stopTimer = setTimeout(() => {
      if (this.active === active) this.fail(new Error('未确认 Codex 已停止；队列已保留，请检查后继续'));
    }, this.interruptTimeout);
    active.stopTimer.unref?.();
  }
  dispose() {
    this.disposed = true;
    if (this.active) this.finish('interrupted');
    this.rpc?.close(); this.rpc = null;
  }
  fail(error) {
    if (this.active) {
      this.store.addMessage(this.session.id, { role: 'system', text: `Codex 连接失败：${error.message}。未完成的发送不会自动重试。` });
      this.store.pauseQueue(this.session.id);
      this.finish('failed');
    }
    const rpc = this.rpc; this.rpc = null; rpc?.close();
  }
  cancelRequests(active) {
    for (const controller of active.requests.values()) controller.abort();
    active.requests.clear();
  }
  finish(status, error) {
    const active = this.active; if (!active) return;
    active.finished = true;
    this.active = null;
    clearTimeout(active.stopTimer); this.cancelRequests(active);
    for (const id of active.streams) this.store.finishMessage(this.session.id, id);
    for (const item of active.items.values()) if (!active.completed.has(item.id)) this.tool(item, true, active, true);
    if (error) this.store.addMessage(this.session.id, { role: 'system', text: `Codex 出错：${error.message ?? error}` });
    if (status === 'failed') this.store.pauseQueue(this.session.id);
    // Release the loaded thread so the next send re-reads any work done in the desktop/terminal.
    // Close before idle can dispatch the next queued message.
    const rpc = this.rpc; this.rpc = null; rpc?.close();
    this.store.setStatus(this.session.id, status === 'failed' ? 'error' : 'idle');
  }

  notification({ method, params: p = {} }) {
    const a = this.active;
    if (!a || (p.threadId && p.threadId !== this.session.agentSessionId)) return;
    if (method === 'turn/started') {
      if (!a.id) a.id = p.turn.id;
      a.delivered = true;
      if (a.stopped) this.interrupt(a);
      return;
    }
    if (!a.id || (p.turnId && p.turnId !== a.id)) return;
    if (method === 'serverRequest/resolved') {
      a.requests.get(p.requestId)?.abort(); a.requests.delete(p.requestId); return;
    }
    if (method === 'turn/completed') {
      if (p.turn.id === a.id) this.finish(p.turn.status, p.turn.error);
      return;
    }
    if (method === 'thread/tokenUsage/updated') { this.usage(p.tokenUsage, a); return; }
    if (method === 'item/agentMessage/delta' || method === 'item/plan/delta') {
      if (a.completed.has(p.itemId)) return;
      const id = `${a.prefix}-${p.itemId}`;
      a.streams.add(id); this.store.appendDelta(this.session.id, id, p.delta); return;
    }
    if (method !== 'item/started' && method !== 'item/completed') return;
    const item = p.item, done = method === 'item/completed';
    if (!item || a.completed.has(item.id)) return;
    a.items.set(item.id, item);
    if (done) a.completed.add(item.id);
    const id = `${a.prefix}-${item.id}`;
    if (item.type === 'agentMessage' || item.type === 'plan') {
      if (done) {
        // Only append missing text; iOS receives deltas immediately, including the final suffix.
        const existing = this.store.messagesOf(this.session.id).find(m => m.id === id)?.text ?? '';
        if (!existing || item.text.startsWith(existing)) this.store.appendDelta(this.session.id, id, item.text.slice(existing.length));
        else this.store.replaceMessageText(this.session.id, id, item.text);
        this.store.finishMessage(this.session.id, id); a.streams.delete(id);
      }
    } else this.tool(item, done, a);
  }

  tool(item, done, a, interrupted = false) {
    const id = `${a.prefix}-${item.id}`;
    let name, detail, output = null, outputKind = 'text';
    switch (item.type) {
      case 'commandExecution': name = 'Shell'; detail = item.command; output = item.aggregatedOutput; break;
      case 'fileChange':
        name = 'Edit'; detail = item.changes.map(c => c.path).join(', ');
        output = item.changes.map(c => c.diff).filter(Boolean).join('\n'); outputKind = 'diff'; break;
      case 'mcpToolCall': name = `${item.server}.${item.tool}`; detail = JSON.stringify(item.arguments); output = JSON.stringify(item.result); break;
      case 'dynamicToolCall': name = item.tool; detail = JSON.stringify(item.arguments); break;
      case 'webSearch': name = 'WebSearch'; detail = item.query; break;
      case 'imageView': name = 'ViewImage'; detail = item.path; break;
      case 'imageGeneration': name = 'ImageGen'; detail = item.revisedPrompt ?? '生成图片'; break;
      case 'collabAgentToolCall': name = item.tool; detail = item.prompt ?? item.receiverThreadIds.join(', '); break;
      default: return;
    }
    const failed = interrupted || ['failed', 'declined'].includes(item.status) || (item.exitCode != null && item.exitCode !== 0);
    this.store.upsertToolCall(this.session.id, { id, name, detail: detail ?? '',
      state: !done ? 'running' : failed ? 'error' : 'done', ...(done && output ? { output, outputKind } : {}) }, `${a.prefix}-tools`);
    if (done && !failed && item.type === 'imageGeneration' && (item.savedPath || item.result)) {
      let target = item.savedPath;
      if (!target) {
        const upload = this.store.addUpload('codex-generated.png', 'image/png', Buffer.from(item.result, 'base64'));
        target = this.store.upload(upload).path;
      }
      this.store.appendDelta(this.session.id, `${id}-image`, `![生成的图片](<${target}>)`);
      this.store.finishMessage(this.session.id, `${id}-image`);
    }
  }

  usage(u, a) {
    if (!u?.last || !u.total) return;
    const keys = ['inputTokens', 'cachedInputTokens', 'outputTokens', 'reasoningOutputTokens'];
    if (a.totals && keys.every(k => a.totals[k] === u.total[k])) return;
    const delta = Object.fromEntries(keys.map(k => [k, Math.max(0, a.totals ? (u.total[k] ?? 0) - (a.totals[k] ?? 0) : u.last[k] ?? 0)]));
    a.totals = u.total;
    const prev = a.usage ?? { input: 0, cacheWrite: 0, cacheRead: 0, output: 0, thinking: 0 };
    a.usage = { model: this.session.model ?? this.defaultModel ?? null,
      input: prev.input + Math.max(0, delta.inputTokens - delta.cachedInputTokens), cacheWrite: 0,
      cacheRead: prev.cacheRead + delta.cachedInputTokens, output: prev.output + delta.outputTokens,
      thinking: prev.thinking + delta.reasoningOutputTokens,
      contextTokens: u.last.totalTokens ?? u.last.inputTokens + u.last.outputTokens,
      contextWindow: u.modelContextWindow ?? null, costUSD: null, durationMs: Date.now() - a.startedAt };
    this.store.setUsage(this.session.id, { ...accumulateUsage(a.previousUsage, a.usage), source: 'app-server' });
  }

  async serverRequest(rpc, { id, method, params: p = {} }) {
    const a = this.active;
    if (rpc !== this.rpc || !a || a.stopped || p.threadId !== this.session.agentSessionId || (p.turnId && p.turnId !== a.id)) {
      rpc.reject(id, 'This turn is no longer active'); return;
    }
    const controller = new AbortController(); a.requests.set(id, controller);
    let request, reply;
    const item = a.items.get(p.itemId);
    if (method === 'item/commandExecution/requestApproval') {
      const command = p.command ?? item?.command ?? '(命令未提供)';
      request = { ...classifyPermission('Bash', { command }), toolName: 'Bash',
        detail: [command, p.cwd && `目录：${p.cwd}`, p.reason, p.networkApprovalContext && JSON.stringify(p.networkApprovalContext)].filter(Boolean).join('\n'),
        allowRules: Boolean(p.command ?? item?.command) && !p.networkApprovalContext };
      reply = decision => ({ decision: decision === 'deny' ? 'decline' : 'accept' });
    } else if (method === 'item/fileChange/requestApproval') {
      request = { kind: 'write', risk: 'medium', toolName: 'Edit', summary: item?.changes?.map(c => c.path).join(', ') || '文件修改',
        detail: [p.reason, p.grantRoot && `请求目录：${p.grantRoot}`, ...(item?.changes ?? []).map(c => `${c.path}\n${c.diff ?? ''}`)].filter(Boolean).join('\n'), allowRules: false };
      reply = decision => ({ decision: decision === 'deny' ? 'decline' : 'accept' });
    } else if (method === 'item/permissions/requestApproval') {
      request = { kind: 'other', risk: 'high', toolName: 'CodexPermissions', summary: p.reason ?? '请求额外访问权限', detail: JSON.stringify(p.permissions, null, 2), allowRules: false };
      reply = decision => ({ permissions: decision === 'deny' ? {} : p.permissions, scope: 'turn' });
    } else if (method === 'item/tool/requestUserInput') {
      request = { kind: 'other', risk: 'low', toolName: 'request_user_input', summary: 'Codex 需要你的回答',
        detail: p.questions.map(q => q.question).join('\n'), questions: p.questions, allowRules: false };
      reply = answer => ({ answers: Object.fromEntries(Object.entries(answer?.answers ?? {}).map(([key, value]) => [key, { answers: [value] }])) });
    } else {
      a.requests.delete(id);
      if (method === 'mcpServer/elicitation/request') rpc.respond(id, { action: 'decline', content: null });
      else rpc.reject(id, `YzVibe does not implement ${method}; ask the user in chat instead`);
      this.store.addMessage(this.session.id, { role: 'system', text: `Codex 请求 ${method} 需要额外交互，请在电脑端处理或让 Codex 改用聊天提问。` });
      return;
    }
    const decision = await this.store.requestApproval({ ...request, sessionId: this.session.id, agent: 'codex', signal: controller.signal });
    if (!controller.signal.aborted && this.active === a && rpc === this.rpc && !a.stopped) rpc.respond(id, reply(decision));
    a.requests.delete(id);
  }
}
