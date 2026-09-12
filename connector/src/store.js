// 会话 / 消息 / 审批 / 设备的内存状态 + JSON 持久化（~/.yzvibe）
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { randomUUID, randomBytes } from 'node:crypto';
import { EventEmitter } from 'node:events';
import { mimeOf } from './files.js';
import { suggestionsFor } from './rules.js';
import { readCodexContext } from './transcripts.js';

export const HOME = process.env.YZVIBE_HOME ?? path.join(os.homedir(), '.yzvibe');

const MAX_TOOL_OUTPUT = 4000;

function readJSON(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; }
}
function writeJSON(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.${randomUUID()}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2), { mode: 0o600 });
  fs.renameSync(tmp, file);
}
/** 工具输出可能是几百 KB 的编译日志，手机上只要看得懂就够了。 */
export function clampOutput(text, max = MAX_TOOL_OUTPUT) {
  const s = String(text ?? '');
  if (s.length <= max) return { output: s, truncated: false };
  const head = s.slice(0, Math.floor(max * 0.6));
  const tail = s.slice(-Math.floor(max * 0.3));
  return { output: `${head}\n…（中间省略 ${s.length - head.length - tail.length} 字）…\n${tail}`, truncated: true };
}

export class Store extends EventEmitter {
  constructor(home = HOME) {
    super();
    this.home = home;
    fs.mkdirSync(path.join(home, 'messages'), { recursive: true });
    this.connector = readJSON(path.join(home, 'connector.json'), null) ?? this.#initConnector();
    this.devices = readJSON(path.join(home, 'devices.json'), []);          // [{ id, name, token, push?, createdAt }]
    this.sessions = readJSON(path.join(home, 'sessions.json'), []).map((s) => ({
      mode: 'normal', model: null, effort: null, usage: null, source: 'phone', branch: null, ...s,
      status: s.status === 'closed' ? 'closed' : 'idle', pendingApprovals: 0,
      queue: (s.queue ?? []).map((q) => ({ ...q, deliveryState: q.deliveryState === 'dispatching' ? 'uncertain' : (q.deliveryState ?? 'queued') })),
      queuePaused: Boolean(s.queue?.length),
    }));
    this.hidden = new Set(readJSON(path.join(home, 'hidden.json'), []));    // 手机上删掉的会话 id（终端会话也不再扫回来）
    this.messages = new Map();                                              // sessionId → Message[]
    this.approvals = [];                                                    // 仅内存：重启后未决审批视为过期
    this.uploads = new Map();                                               // id → { path, mime, name }
    this.rules = null;                                                      // server 注入 Rules 实例
  }

  #initConnector() {
    const c = { id: randomUUID(), createdAt: new Date().toISOString() };
    writeJSON(path.join(this.home, 'connector.json'), c);
    return c;
  }

  // ---------- 设备 ----------
  addDevice(name) {
    const d = { id: randomUUID(), name, token: randomBytes(32).toString('hex'), createdAt: new Date().toISOString(), push: null };
    this.devices.push(d);
    this.#saveDevices();
    return d;
  }
  deviceByToken(token) { return this.devices.find((d) => d.token === token) ?? null; }
  /** 对外展示的设备信息（不含 Token）。 */
  listDevices() {
    return this.devices.map(({ token, push, ...d }) => ({ ...d, push: push ? { environment: push.environment, updatedAt: push.updatedAt } : null }));
  }
  /** 注册 / 更新一台手机的 APNs token。 */
  setDevicePush(deviceId, push) {
    const d = this.devices.find((x) => x.id === deviceId); if (!d) return false;
    d.push = push ? { token: push.token, environment: push.environment ?? 'sandbox', bundleId: push.bundleId ?? null, updatedAt: new Date().toISOString() } : null;
    this.#saveDevices();
    return true;
  }
  /** 手机为某个会话开了实时活动，把它的推送 token 记下来。 */
  setLiveActivity(deviceId, sessionId, { token, environment }) {
    const d = this.devices.find((x) => x.id === deviceId); if (!d) return false;
    d.liveActivities = (d.liveActivities ?? []).filter((a) => a.sessionId !== sessionId && a.token !== token);
    if (token) d.liveActivities.push({ sessionId, token, environment: environment === 'production' ? 'production' : 'sandbox', updatedAt: new Date().toISOString() });
    this.#saveDevices();
    return true;
  }
  /** 某个会话上所有还活着的实时活动。 */
  liveActivitiesFor(sessionId) {
    return this.devices.flatMap((d) => (d.liveActivities ?? []).filter((a) => a.sessionId === sessionId).map((a) => ({ deviceId: d.id, ...a })));
  }
  dropLiveActivity(token) {
    for (const d of this.devices) if (d.liveActivities?.some((a) => a.token === token)) d.liveActivities = d.liveActivities.filter((a) => a.token !== token);
    this.#saveDevices();
  }
  removeDevice(id) {
    const before = this.devices.length;
    this.devices = this.devices.filter((d) => d.id !== id);
    if (this.devices.length === before) return false;
    this.#saveDevices();
    this.emit('device.removed', id);
    return true;
  }
  #saveDevices() { writeJSON(path.join(this.home, 'devices.json'), this.devices); }

  // ---------- 会话 ----------
  createSession({ agent, cwd, title, mode = 'normal', model = null, effort = null }) {
    const now = new Date().toISOString();
    const s = { id: randomUUID(), agent, cwd, title, status: 'idle', createdAt: now, updatedAt: now, pendingApprovals: 0, agentSessionId: null, mode, model, effort, usage: null, source: 'phone', branch: null, queue: [] };
    this.sessions.unshift(s);
    this.messages.set(s.id, []);
    this.#saveSessions();
    this.emit('event', { type: 'session.created', session: this.publicSession(s) });
    return s;
  }
  session(id) { return this.sessions.find((s) => s.id === id) ?? null; }
  /** 接管一个终端里的会话：以它的 id 入库并预填历史消息，之后发消息走 --resume。 */
  adoptSession(imported, messages = []) {
    if (this.session(imported.id)) return this.session(imported.id);
    const { file, ...rest } = imported;
    const s = { ...rest, status: 'idle', pendingApprovals: 0, queue: [] };
    this.sessions.unshift(s);
    this.messages.set(s.id, messages.map((m) => ({ ...m, sessionId: s.id })));
    this.#saveMessages(s.id);
    this.#saveSessions();
    this.emit('event', { type: 'session.created', session: this.publicSession(s) });
    return s;
  }
  publicSession(s) {
    const { agentSessionId, file, ...rest } = s;
    if (s.agent === 'codex' && s.usage?.turn) {
      const context = readCodexContext(agentSessionId) ?? { contextTokens: null, contextWindow: null };
      // 也覆盖旧版持久化的错误上下文值；累计 token 用量保持原样。
      rest.usage = { ...s.usage, turn: { ...s.usage.turn, ...context } };
    }
    return rest;
  }
  listSessions() { return this.sessions.map((s) => this.publicSession(s)); }
  setStatus(id, status) {
    const s = this.session(id); if (!s) return;
    s.status = status; s.updatedAt = new Date().toISOString();
    this.#saveSessions();
    this.emit('event', { type: 'session.status', sessionId: id, status });
  }
  setBaseline(id, sha) {
    const s = this.session(id); if (!s) return;
    s.baseCommit = sha;
    this.#saveSessions();
  }
  setAgentSessionId(id, agentSessionId) { const s = this.session(id); if (s) { s.agentSessionId = agentSessionId; this.#saveSessions(); } }
  /** Agent 自报的可用斜杠命令 / skill（Claude 的 system.init 事件）。 */
  setSessionCatalog(id, { slashCommands, terminalOnly, skills }) {
    const s = this.session(id); if (!s) return;
    if (slashCommands) s.slashCommands = slashCommands;
    if (terminalOnly) s.terminalOnly = terminalOnly;
    if (skills) s.agentSkills = skills;
    this.#saveSessions();
  }
  /** 改 mode / model / effort（已归一化的 patch），广播 session.updated；返回是否有实际变化。 */
  configureSession(id, patch) {
    const s = this.session(id); if (!s) return false;
    let changed = false;
    for (const k of ['mode', 'model', 'effort', 'title']) if (k in patch && s[k] !== patch[k]) { s[k] = patch[k]; changed = true; }
    if (changed) { s.updatedAt = new Date().toISOString(); this.#saveSessions(); this.emit('event', { type: 'session.updated', session: this.publicSession(s) }); }
    return changed;
  }
  /** 一轮结束后记录 token 用量（本轮 + 累计），广播 session.updated。 */
  setUsage(id, usage) {
    const s = this.session(id); if (!s) return;
    s.usage = usage; s.updatedAt = new Date().toISOString();
    this.#saveSessions();
    this.emit('event', { type: 'session.updated', session: this.publicSession(s) });
  }
  closeSession(id) {
    this.rules?.removeForSession(id);
    const s = this.session(id); if (s) s.queue = [];
    this.setStatus(id, 'closed');
  }

  // ---------- 待发送队列 ----------
  // Agent 正忙时再发消息不该被丢掉，也不该默认打断它——排进队列，本轮结束自动接上。

  /** @param front true 时插到队首（「立即发送」会配合打断当前轮一起用）。 */
  enqueue(sessionId, { text = '', attachments = [] }, { front = false } = {}) {
    const s = this.session(sessionId); if (!s) return null;
    const item = { id: randomUUID(), text, attachments, createdAt: new Date().toISOString(), deliveryState: 'queued' };
    s.queue = s.queue ?? [];
    if (front) s.queue.unshift(item); else s.queue.push(item);
    s.updatedAt = item.createdAt;
    this.#saveSessions();
    this.emit('event', { type: 'session.updated', session: this.publicSession(s) });
    return item;
  }
  prioritizeQueued(sessionId, itemId) {
    const s = this.session(sessionId);
    const item = s?.queue?.find(q => q.id === itemId);
    if (!item) throw Object.assign(new Error('排队消息已发送或已移除'), { status: 404 });
    if (item.deliveryState !== 'queued' || s.queue.some(q => q.deliveryState !== 'queued'))
      throw Object.assign(new Error('队列正在发送或结果待确认，请稍后重试'), { status: 409 });
    s.queue = [item, ...s.queue.filter(q => q.id !== itemId)];
    s.queuePaused = false;
    this.#saveSessions();
    this.emit('event', { type: 'session.updated', session: this.publicSession(s) });
  }
  dequeue(sessionId) {
    const s = this.session(sessionId); if (!s?.queue?.length) return null;
    const item = s.queue.shift();
    this.#saveSessions();
    this.emit('event', { type: 'session.updated', session: this.publicSession(s) });
    return item;
  }
  pauseQueue(sessionId) {
    const s = this.session(sessionId); if (!s) return;
    s.queuePaused = Boolean(s.queue?.length);
    this.#saveSessions();
    this.emit('event', { type: 'session.updated', session: this.publicSession(s) });
  }
  resumeQueue(sessionId) {
    const s = this.session(sessionId); if (!s) return;
    if (s.queue?.some((q) => q.deliveryState === 'uncertain')) throw Object.assign(new Error('有发送结果待确认的消息，请先检查历史并移除此项'), { status: 409 });
    s.queuePaused = false;
    this.#saveSessions();
    this.emit('event', { type: 'session.updated', session: this.publicSession(s) });
  }
  markQueued(sessionId, itemId, deliveryState) {
    const s = this.session(sessionId), item = s?.queue?.find((q) => q.id === itemId);
    if (!item) return;
    item.deliveryState = deliveryState;
    this.#saveSessions();
    this.emit('event', { type: 'session.updated', session: this.publicSession(s) });
  }
  cancelQueued(sessionId, itemId) {
    const s = this.session(sessionId); if (!s?.queue?.length) return false;
    const before = s.queue.length;
    s.queue = s.queue.filter((x) => x.id !== itemId);
    if (s.queue.length === before) return false;
    if (!s.queue.length) s.queuePaused = false;
    this.#saveSessions();
    this.emit('event', { type: 'session.updated', session: this.publicSession(s) });
    return true;
  }
  /** 手机上「删除会话」：清掉本地记录，并记住不要再从 transcript 扫回来。transcript 原文不动。 */
  deleteSession(id) {
    for (const a of this.approvals.filter((x) => x.sessionId === id && x.status === 'pending')) this.resolveApproval(a.id, 'deny', 'system');
    this.rules?.removeForSession(id);
    this.sessions = this.sessions.filter((s) => s.id !== id);
    this.messages.delete(id);
    try { fs.rmSync(path.join(this.home, 'messages', `${id}.json`)); } catch {}
    this.hidden.add(id);
    this.#saveHidden();
    this.#saveSessions();
    this.emit('event', { type: 'session.removed', sessionId: id });
    return true;
  }
  isHidden(id) { return this.hidden.has(id); }
  listHidden() { return [...this.hidden]; }
  /** 恢复：不传 id 就把隐藏列表整个清空（终端会话下次扫描会重新出现）。 */
  restoreHidden(id = null) {
    if (id === null) { const n = this.hidden.size; this.hidden.clear(); this.#saveHidden(); return n; }
    const had = this.hidden.delete(id);
    if (had) this.#saveHidden();
    return had ? 1 : 0;
  }
  #saveHidden() { writeJSON(path.join(this.home, 'hidden.json'), [...this.hidden]); }

  /** 清理时彻底忘掉一批会话（消息文件已由 cleanup 删除）。 */
  forgetSessions(ids) {
    const set = new Set(ids);
    this.sessions = this.sessions.filter((s) => !set.has(s.id));
    for (const id of set) { this.messages.delete(id); this.rules?.removeForSession(id); }
    this.#saveSessions();
  }
  #saveSessions() { writeJSON(path.join(this.home, 'sessions.json'), this.sessions); }

  // ---------- 消息 ----------
  messagesOf(sessionId) {
    if (!this.messages.has(sessionId)) this.messages.set(sessionId, readJSON(path.join(this.home, 'messages', `${sessionId}.json`), []));
    return this.messages.get(sessionId);
  }
  #saveMessages(sessionId) { writeJSON(path.join(this.home, 'messages', `${sessionId}.json`), this.messagesOf(sessionId)); }
  addMessage(sessionId, partial) {
    const m = { id: randomUUID(), sessionId, role: 'assistant', text: '', attachments: [], toolCalls: [], approvalId: null, createdAt: new Date().toISOString(), streaming: false, ...partial };
    this.messagesOf(sessionId).push(m);
    this.#saveMessages(sessionId);
    const s = this.session(sessionId);
    if (s) {
      s.updatedAt = m.createdAt;
      if (m.role === 'user' && (!s.title || s.title === '新会话') && m.text.trim()) {
        s.title = m.text.trim().slice(0, 40);
        this.emit('event', { type: 'session.updated', session: this.publicSession(s) });
      }
      this.#saveSessions();
    }
    if (m.role === 'system') this.emit('event', { type: 'message.added', sessionId, message: m });
    return m;
  }
  /** 拿到（必要时新建）某个 id 的助手消息，用来把同一轮的工具卡归到同一个气泡里。 */
  ensureAssistantMessage(sessionId, messageId) {
    return this.messagesOf(sessionId).find((x) => x.id === messageId)
        ?? this.addMessage(sessionId, { id: messageId, role: 'assistant' });
  }
  appendDelta(sessionId, messageId, text) {
    const list = this.messagesOf(sessionId);
    let m = list.find((x) => x.id === messageId);
    if (!m) m = this.addMessage(sessionId, { id: messageId, role: 'assistant', streaming: true });
    m.text += text;
    this.emit('event', { type: 'message.delta', sessionId, messageId, role: 'assistant', text });
    return m;
  }
  finishMessage(sessionId, messageId, fullText) {
    const m = this.messagesOf(sessionId).find((x) => x.id === messageId);
    if (m) { if (typeof fullText === 'string') m.text = fullText; m.streaming = false; this.#saveMessages(sessionId); }
    this.emit('event', { type: 'message.done', sessionId, messageId });
  }
  /**
   * 新增 / 更新一张工具卡。`output` 是工具的实际输出（Bash 的 stdout、Edit 的 diff），
   * 手机上可以展开看——之前只显示「运行中 / 完成」，看不到结果就没法判断该不该批下一步。
   */
  upsertToolCall(sessionId, call, messageId = null) {
    const list = this.messagesOf(sessionId);
    // 先找真正包含这个工具的消息（工具结果可能晚于新消息到达），其次是本轮指定的消息，最后才退回最后一条助手消息
    let m = [...list].reverse().find((x) => x.toolCalls?.some((t) => t.id === call.id));
    if (!m && messageId) m = this.ensureAssistantMessage(sessionId, messageId);
    if (!m) m = [...list].reverse().find((x) => x.role === 'assistant') ?? this.addMessage(sessionId, { role: 'assistant' });
    const patch = { ...call };
    if (patch.output != null) {
      const { output, truncated } = clampOutput(patch.output);
      patch.output = output; patch.truncated = truncated;
    }
    const i = m.toolCalls.findIndex((t) => t.id === call.id);
    if (i >= 0) {
      // diff 预览不要被工具返回的成功提示覆盖掉
      if (m.toolCalls[i].outputKind === 'diff' && patch.outputKind == null && patch.state !== 'error') delete patch.output;
      m.toolCalls[i] = { ...m.toolCalls[i], ...patch };
    } else {
      m.toolCalls.push({ output: null, outputKind: 'text', truncated: false, ...patch });
    }
    this.#saveMessages(sessionId);
    const t = m.toolCalls[i >= 0 ? i : m.toolCalls.length - 1];
    this.emit('event', { type: 'tool.call', sessionId, messageId: m.id, toolId: t.id, name: t.name, input: { detail: t.detail }, state: t.state,
                         output: t.output ?? null, outputKind: t.outputKind ?? 'text', truncated: Boolean(t.truncated) });
  }

  // ---------- 审批 ----------
  /**
   * 返回 Promise<'allow'|'deny'|'allow_once'>。命中已保存的审批规则时立刻放行，
   * 并在聊天里留一条系统消息说明是哪条规则放的，避免「悄悄执行了」。
   */
  requestApproval({ sessionId, kind, summary, detail, risk, toolName, agent }) {
    const rule = this.rules?.match({ sessionId, agent, toolName, summary });
    if (rule) {
      this.addMessage(sessionId, { role: 'system', text: `已按规则自动允许：${summary}`, ruleId: rule.id });
      return Promise.resolve('allow');
    }
    const a = {
      id: randomUUID(), sessionId, deviceId: this.connector.id, kind, summary, detail, risk,
      status: 'pending', createdAt: new Date().toISOString(), expiresAt: new Date(Date.now() + 10 * 60_000).toISOString(),
      toolName, agent: agent ?? null, suggestions: suggestionsFor({ toolName, kind, summary }),
    };
    this.approvals.unshift(a);
    const s = this.session(sessionId); if (s) { s.pendingApprovals += 1; }
    this.addMessage(sessionId, { role: 'system', approvalId: a.id });
    this.setStatus(sessionId, 'waiting_approval');
    this.emit('event', { type: 'approval.requested', ...this.publicApproval(a) });
    return new Promise((resolve) => {
      a.resolve = resolve;
      a.timer = setTimeout(() => this.resolveApproval(a.id, 'deny', 'timeout'), 10 * 60_000);
      a.timer.unref?.();
    });
  }
  publicApproval(a) { const { resolve, timer, ...rest } = a; return { ...rest, approvalId: a.id }; }
  approval(id) { return this.approvals.find((a) => a.id === id) ?? null; }
  listApprovals(status) { return this.approvals.filter((a) => !status || a.status === status).map((a) => this.publicApproval(a)); }
  /**
   * @param remember 可选 `{ match, value, scope, ttlMinutes }`：把这次的决定存成规则，以后同类请求自动放行。
   */
  resolveApproval(id, decision, by = 'phone', remember = null) {
    const a = this.approvals.find((x) => x.id === id);
    if (!a || a.status !== 'pending' || !['allow', 'deny', 'allow_once'].includes(decision)) return false;
    clearTimeout(a.timer);
    a.status = by === 'timeout' ? 'expired' : decision === 'deny' ? 'denied' : 'allowed';
    let rule = null;
    if (remember && decision !== 'deny' && this.rules) {
      try {
        rule = this.rules.add({ sessionId: a.sessionId, agent: a.agent, tool: remember.match === 'tool' ? a.toolName : (remember.tool ?? null),
                                match: remember.match ?? 'tool', value: remember.value ?? a.toolName, scope: remember.scope ?? 'session',
                                ttlMinutes: remember.ttlMinutes ?? null, label: remember.label ?? null });
        this.addMessage(a.sessionId, { role: 'system', text: `已记住规则：${rule.label ?? describeRule(rule)}`, ruleId: rule.id });
      } catch (e) { this.addMessage(a.sessionId, { role: 'system', text: `规则未保存：${e.message}` }); }
    }
    const s = this.session(a.sessionId); if (s) { s.pendingApprovals = Math.max(0, s.pendingApprovals - 1); }
    // 拒绝工具不代表 Agent 已结束本轮；只有 Agent 的结束事件才能推进队列。
    this.setStatus(a.sessionId, 'running');
    this.emit('event', { type: 'approval.resolved', approvalId: id, decision, by, rule });
    a.resolve?.(decision);
    return true;
  }

  // ---------- 上传 ----------
  /** 取上传记录；内存里没有（连接器重启过）就按 id 前缀在 uploads 目录找回。 */
  upload(id) {
    if (this.uploads.has(id)) return this.uploads.get(id);
    if (!/^[\w-]+$/.test(id)) return null;
    const dir = path.join(this.home, 'uploads');
    let names; try { names = fs.readdirSync(dir); } catch { return null; }
    const n = names.find((x) => x.startsWith(`${id}-`)); if (!n) return null;
    const u = { path: path.join(dir, n), mime: mimeOf(n), name: n.slice(id.length + 1) };
    this.uploads.set(id, u);
    return u;
  }
  addUpload(name, mime, buffer) {
    const id = randomUUID();
    const file = path.join(this.home, 'uploads', `${id}-${name.replace(/[^\w.\-]/g, '_')}`);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, buffer);
    this.uploads.set(id, { path: file, mime, name });
    return id;
  }
}

/** 规则的中文描述（手机端和日志共用）。 */
export function describeRule(r) {
  const where = r.scope === 'global' ? '所有会话' : '本会话';
  const until = r.expiresAt ? `，到 ${new Date(r.expiresAt).toLocaleString('zh-CN', { hour12: false })}` : '';
  if (r.match === 'tool') return `${where}内不再询问 ${r.value ?? r.tool}${until}`;
  if (r.match === 'prefix') return `${where}内放行以 ${r.value} 开头的命令${until}`;
  return `${where}内放行 ${r.value}${until}`;
}
