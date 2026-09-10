// 会话 / 消息 / 审批 / 设备的内存状态 + JSON 持久化（~/.yzvibe）
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { randomUUID, randomBytes } from 'node:crypto';
import { EventEmitter } from 'node:events';
import { mimeOf } from './files.js';

export const HOME = process.env.YZVIBE_HOME ?? path.join(os.homedir(), '.yzvibe');

function readJSON(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; }
}
function writeJSON(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(data, null, 2));
}

export class Store extends EventEmitter {
  constructor(home = HOME) {
    super();
    this.home = home;
    fs.mkdirSync(path.join(home, 'messages'), { recursive: true });
    this.connector = readJSON(path.join(home, 'connector.json'), null) ?? this.#initConnector();
    this.devices = readJSON(path.join(home, 'devices.json'), []);          // [{ id, name, token, createdAt }]
    this.sessions = readJSON(path.join(home, 'sessions.json'), []).map((s) => ({ mode: 'normal', model: null, effort: null, usage: null, source: 'phone', branch: null, ...s, status: s.status === 'closed' ? 'closed' : 'idle', pendingApprovals: 0 }));
    this.messages = new Map();                                              // sessionId → Message[]
    this.approvals = [];                                                    // 仅内存：重启后未决审批视为过期
    this.autoAllow = new Map();                                             // `${sessionId}:${toolName}:${summary}` → true
    this.uploads = new Map();                                               // id → { path, mime, name }
  }

  #initConnector() {
    const c = { id: randomUUID(), createdAt: new Date().toISOString() };
    writeJSON(path.join(this.home, 'connector.json'), c);
    return c;
  }

  // ---------- 设备 ----------
  addDevice(name) {
    const d = { id: randomUUID(), name, token: randomBytes(32).toString('hex'), createdAt: new Date().toISOString() };
    this.devices.push(d);
    writeJSON(path.join(this.home, 'devices.json'), this.devices);
    return d;
  }
  deviceByToken(token) { return this.devices.find((d) => d.token === token) ?? null; }

  // ---------- 会话 ----------
  createSession({ agent, cwd, title, mode = 'normal', model = null, effort = null }) {
    const now = new Date().toISOString();
    const s = { id: randomUUID(), agent, cwd, title, status: 'idle', createdAt: now, updatedAt: now, pendingApprovals: 0, agentSessionId: null, mode, model, effort, usage: null, source: 'phone', branch: null };
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
    const s = { ...rest, status: 'idle', pendingApprovals: 0 };
    this.sessions.unshift(s);
    this.messages.set(s.id, messages.map((m) => ({ ...m, sessionId: s.id })));
    this.#saveMessages(s.id);
    this.#saveSessions();
    this.emit('event', { type: 'session.created', session: this.publicSession(s) });
    return s;
  }
  publicSession(s) { const { agentSessionId, file, ...rest } = s; return rest; }
  listSessions() { return this.sessions.map((s) => this.publicSession(s)); }
  setStatus(id, status) {
    const s = this.session(id); if (!s) return;
    s.status = status; s.updatedAt = new Date().toISOString();
    this.#saveSessions();
    this.emit('event', { type: 'session.status', sessionId: id, status });
  }
  setAgentSessionId(id, agentSessionId) { const s = this.session(id); if (s) { s.agentSessionId = agentSessionId; this.#saveSessions(); } }
  /** 改 mode / model / effort（已归一化的 patch），广播 session.updated；返回是否有实际变化。 */
  configureSession(id, patch) {
    const s = this.session(id); if (!s) return false;
    let changed = false;
    for (const k of ['mode', 'model', 'effort']) if (k in patch && s[k] !== patch[k]) { s[k] = patch[k]; changed = true; }
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
  closeSession(id) { this.setStatus(id, 'closed'); }
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
    return m;
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
  upsertToolCall(sessionId, call) {
    const list = this.messagesOf(sessionId);
    let m = [...list].reverse().find((x) => x.role === 'assistant');
    if (!m) m = this.addMessage(sessionId, { role: 'assistant' });
    const i = m.toolCalls.findIndex((t) => t.id === call.id);
    if (i >= 0) m.toolCalls[i] = { ...m.toolCalls[i], ...call }; else m.toolCalls.push(call);
    this.#saveMessages(sessionId);
    this.emit('event', { type: 'tool.call', sessionId, toolId: call.id, name: call.name, input: { detail: call.detail }, state: call.state });
  }

  // ---------- 审批 ----------
  /** 返回 Promise<'allow'|'deny'|'allow_once'>；若命中 autoAllow 立即 resolve。 */
  requestApproval({ sessionId, kind, summary, detail, risk, toolName }) {
    const key = `${sessionId}:${toolName}:${summary}`;
    if (this.autoAllow.has(key)) return Promise.resolve('allow');
    const a = { id: randomUUID(), sessionId, deviceId: this.connector.id, kind, summary, detail, risk, status: 'pending', createdAt: new Date().toISOString(), expiresAt: new Date(Date.now() + 10 * 60_000).toISOString(), toolName };
    this.approvals.unshift(a);
    const s = this.session(sessionId); if (s) { s.pendingApprovals += 1; }
    this.addMessage(sessionId, { role: 'system', approvalId: a.id });
    this.setStatus(sessionId, 'waiting_approval');
    this.emit('event', { type: 'approval.requested', ...this.publicApproval(a) });
    return new Promise((resolve) => {
      a.resolve = resolve;
      a.timer = setTimeout(() => this.resolveApproval(a.id, 'deny', 'timeout'), 10 * 60_000);
    });
  }
  publicApproval(a) { const { resolve, timer, toolName, ...rest } = a; return { ...rest, approvalId: a.id }; }
  listApprovals(status) { return this.approvals.filter((a) => !status || a.status === status).map((a) => this.publicApproval(a)); }
  resolveApproval(id, decision, by = 'phone') {
    const a = this.approvals.find((x) => x.id === id);
    if (!a || a.status !== 'pending') return false;
    clearTimeout(a.timer);
    a.status = by === 'timeout' ? 'expired' : decision === 'deny' ? 'denied' : 'allowed';
    if (decision === 'allow') this.autoAllow.set(`${a.sessionId}:${a.toolName}:${a.summary}`, true);
    const s = this.session(a.sessionId); if (s) { s.pendingApprovals = Math.max(0, s.pendingApprovals - 1); }
    this.setStatus(a.sessionId, decision === 'deny' ? 'idle' : 'running');
    this.emit('event', { type: 'approval.resolved', approvalId: id, decision, by });
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
