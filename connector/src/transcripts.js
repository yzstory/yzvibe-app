// 读取本机终端里已经进行过的会话：Claude Code（~/.claude/projects/*/*.jsonl）与 Codex（~/.codex/sessions/**/rollout-*.jsonl）。
// 只解析头部信息做列表；手机打开某个会话时再把整份 transcript 翻译成我们的 Message 结构，并在 store 里「接管」它，
// 之后发消息就走 --resume / exec resume，和手机自己建的会话一样。
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export const CLAUDE_HOME = process.env.CLAUDE_CONFIG_DIR ?? path.join(os.homedir(), '.claude');
export const CODEX_HOME = process.env.CODEX_HOME ?? path.join(os.homedir(), '.codex');

const MAX_FILES = 80;                 // 每种 Agent 最多看最近多少个文件
const MAX_AGE_MS = 45 * 86400_000;    // 太久远的不列
const HEAD_BYTES = 256 * 1024;        // 列表只读文件头
const MAX_MESSAGES = 300;             // 打开会话时最多带多少条历史

const headerCache = new Map();        // file → { mtimeMs, size, header }

const lines = (text) => text.split('\n').map((l) => l.trim()).filter(Boolean);
const parse = (l) => { try { return JSON.parse(l); } catch { return null; } };
const stripTags = (t) => String(t).replace(/<[^>]+>[\s\S]*?<\/[^>]+>/g, '').replace(/<[^>]+>/g, '').trim();
const textOf = (content) => {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content.filter((b) => b?.type === 'text' || b?.type === 'input_text' || b?.type === 'output_text').map((b) => b.text ?? '').join('\n');
};
/** Codex 注入的项目说明 / 环境上下文，不是用户说的话。 */
const isInjected = (t) => /^(# AGENTS\.md instructions|<environment_context>|<permissions instructions>|<user_instructions>|<recommended_plugins>)/.test(String(t).trimStart());
const title = (t) => (isInjected(t) ? null : stripTags(t).replace(/\s+/g, ' ').slice(0, 60) || null);

function readHead(file) {
  const fd = fs.openSync(file, 'r');
  try { const buf = Buffer.alloc(HEAD_BYTES); const n = fs.readSync(fd, buf, 0, HEAD_BYTES, 0); return buf.toString('utf8', 0, n); }
  finally { fs.closeSync(fd); }
}
function readTail(file, bytes = 64 * 1024) {
  const { size } = fs.statSync(file);
  const fd = fs.openSync(file, 'r');
  try { const start = Math.max(0, size - bytes); const buf = Buffer.alloc(size - start); fs.readSync(fd, buf, 0, buf.length, start); return buf.toString('utf8'); }
  finally { fs.closeSync(fd); }
}

function cached(file, stat, compute) {
  const hit = headerCache.get(file);
  if (hit && hit.mtimeMs === stat.mtimeMs && hit.size === stat.size) return hit.header;
  const header = compute();
  headerCache.set(file, { mtimeMs: stat.mtimeMs, size: stat.size, header });
  return header;
}

function recentFiles(globDirs, pattern) {
  const out = [];
  for (const dir of globDirs) {
    let names; try { names = fs.readdirSync(dir); } catch { continue; }
    for (const n of names) {
      if (!pattern.test(n)) continue;
      const file = path.join(dir, n);
      let st; try { st = fs.statSync(file); } catch { continue; }
      if (!st.isFile() || st.size < 200 || Date.now() - st.mtimeMs > MAX_AGE_MS) continue;
      out.push({ file, st });
    }
  }
  return out.sort((a, b) => b.st.mtimeMs - a.st.mtimeMs).slice(0, MAX_FILES);
}

// ---------- Claude Code ----------

function claudeHeader(file, st) {
  return cached(file, st, () => {
    const head = readHead(file);
    let cwd = null, branch = null, entrypoint = null, firstUser = null, created = null;
    for (const l of lines(head)) {
      const e = parse(l); if (!e) continue;
      if (!cwd && e.cwd) { cwd = e.cwd; branch = e.gitBranch ?? null; entrypoint = e.entrypoint ?? null; created = e.timestamp ?? null; }
      if (!firstUser && e.type === 'user' && !e.isMeta && e.message?.role === 'user') {
        const t = title(textOf(e.message.content));
        if (t && !/^<?(local-command|command-name)/.test(t)) firstUser = t;
      }
      if (cwd && firstUser) break;
    }
    if (!cwd || !fs.existsSync(cwd)) return null;   // 临时目录已删的会话不列
    // ai-title 出现在文件靠后位置，从尾部找最新的一条
    let aiTitle = null;
    const tail = readTail(file);
    const m = [...tail.matchAll(/"aiTitle":"((?:[^"\\]|\\.)*)"/g)];
    if (m.length) { try { aiTitle = JSON.parse(`"${m.at(-1)[1]}"`); } catch {} }
    if (!aiTitle) { const h = [...head.matchAll(/"aiTitle":"((?:[^"\\]|\\.)*)"/g)]; if (h.length) { try { aiTitle = JSON.parse(`"${h.at(-1)[1]}"`); } catch {} } }
    if (!aiTitle && !firstUser) return null;
    return { sessionId: path.basename(file, '.jsonl'), cwd, branch, entrypoint, title: aiTitle ?? firstUser, createdAt: created };
  });
}

export function scanClaudeSessions({ claudeHome = CLAUDE_HOME } = {}) {
  const root = path.join(claudeHome, 'projects');
  let dirs; try { dirs = fs.readdirSync(root).map((d) => path.join(root, d)); } catch { return []; }
  const out = [];
  for (const { file, st } of recentFiles(dirs, /\.jsonl$/)) {
    const h = claudeHeader(file, st); if (!h) continue;
    out.push({
      id: `claude:${h.sessionId}`, agent: 'claude', agentSessionId: h.sessionId, cwd: h.cwd, title: h.title, branch: h.branch,
      source: h.entrypoint === 'cli' ? 'terminal' : 'sdk', status: 'idle', pendingApprovals: 0,
      createdAt: h.createdAt ?? new Date(st.birthtimeMs || st.mtimeMs).toISOString(), updatedAt: new Date(st.mtimeMs).toISOString(),
      mode: 'normal', model: null, effort: null, usage: null, file,
    });
  }
  return out;
}

/** 整份 Claude transcript → Message[]（按 API message id 合并内容块，tool_result 回填工具状态）。 */
export function parseClaudeTranscript(file, sessionId) {
  const msgs = []; const byApiId = new Map(); const toolIndex = new Map();
  let text; try { text = fs.readFileSync(file, 'utf8'); } catch { return []; }
  for (const l of lines(text)) {
    const e = parse(l); if (!e || e.isSidechain) continue;
    if (e.type === 'user' && e.message?.role === 'user') {
      const content = e.message.content;
      const blocks = Array.isArray(content) ? content : [{ type: 'text', text: content }];
      for (const b of blocks) if (b?.type === 'tool_result') { const ref = toolIndex.get(b.tool_use_id); if (ref) ref.state = b.is_error ? 'error' : 'done'; }
      if (e.isMeta) continue;
      const t = stripTags(textOf(blocks));
      if (!t || /^(<command-name>|<local-command)/.test(t)) continue;
      const images = blocks.filter((b) => b?.type === 'image').length;
      msgs.push({ id: e.uuid ?? `u-${msgs.length}`, sessionId, role: 'user', text: images ? `${t}${t ? '\n' : ''}（${images} 张图片）` : t, attachments: [], toolCalls: [], approvalId: null, createdAt: e.timestamp ?? new Date().toISOString(), streaming: false });
    } else if (e.type === 'assistant' && e.message) {
      const key = e.message.id ?? e.uuid;
      let m = byApiId.get(key);
      if (!m) { m = { id: e.uuid ?? `a-${msgs.length}`, sessionId, role: 'assistant', text: '', attachments: [], toolCalls: [], approvalId: null, createdAt: e.timestamp ?? new Date().toISOString(), streaming: false }; byApiId.set(key, m); msgs.push(m); }
      for (const b of e.message.content ?? []) {
        if (b.type === 'text' && b.text) m.text += (m.text ? '\n' : '') + b.text;
        else if (b.type === 'tool_use') { const call = { id: b.id, name: b.name, detail: summarize(b.input), state: 'done' }; m.toolCalls.push(call); toolIndex.set(b.id, call); }
      }
    }
  }
  return msgs.filter((m) => m.text || m.toolCalls.length).slice(-MAX_MESSAGES);
}

// ---------- Codex ----------

function codexHeader(file, st) {
  return cached(file, st, () => {
    const head = readHead(file);
    let meta = null, firstUser = null, fallbackUser = null;
    for (const l of lines(head)) {
      const e = parse(l); if (!e) continue;
      if (e.type === 'session_meta') meta = e.payload;
      if (e.type === 'event_msg' && e.payload?.type === 'user_message' && !firstUser) firstUser = title(e.payload.message);
      // Codex Desktop / app-server 只写 response_item，没有 user_message 事件
      if (e.type === 'response_item' && e.payload?.type === 'message' && e.payload.role === 'user' && !fallbackUser) fallbackUser = title(textOf(e.payload.content));
      if (meta && firstUser) break;
    }
    firstUser = firstUser ?? fallbackUser;
    if (!meta?.cwd || !firstUser || !fs.existsSync(meta.cwd)) return null;
    return { sessionId: meta.id ?? meta.session_id ?? path.basename(file, '.jsonl'), cwd: meta.cwd, title: firstUser, createdAt: meta.timestamp ?? null, originator: meta.originator ?? null, source: meta.source ?? null };
  });
}

function codexDirs(codexHome) {
  const root = path.join(codexHome, 'sessions'); const out = [];
  try { for (const y of fs.readdirSync(root)) for (const m of fs.readdirSync(path.join(root, y))) for (const d of fs.readdirSync(path.join(root, y, m))) out.push(path.join(root, y, m, d)); } catch {}
  return out;
}

const codexContextFiles = new Map();
const codexContextCache = new Map();

/** 只读取指定线程最后一次 token_count；不以整轮累计或其他线程的数据代替。 */
export function readCodexContext(threadId, { codexHome = CODEX_HOME } = {}) {
  if (!threadId || !/^[a-zA-Z0-9-]+$/.test(threadId)) return null;
  const key = `${codexHome}:${threadId}`;
  try {
    let file = codexContextFiles.get(key);
    if (!file || !fs.existsSync(file)) {
      for (const dir of codexDirs(codexHome)) {
        const name = fs.readdirSync(dir).find((n) => n.startsWith('rollout-') && n.endsWith(`-${threadId}.jsonl`));
        if (name) { file = path.join(dir, name); break; }
      }
      if (!file) return null;
      codexContextFiles.set(key, file);
    }
    const st = fs.statSync(file);
    const hit = codexContextCache.get(key);
    if (hit?.size === st.size && hit?.mtimeMs === st.mtimeMs) return hit.value;
    let value = null;
    for (const line of lines(readTail(file, 1024 * 1024)).reverse()) {
      const e = parse(line);
      if (e?.type !== 'event_msg' || e.payload?.type !== 'token_count' || !e.payload.info) continue;
      const info = e.payload.info, last = info.last_token_usage;
      const input = last?.input_tokens, output = last?.output_tokens, window = info.model_context_window;
      if (Number.isFinite(input) && input >= 0 && Number.isFinite(output) && output >= 0 && Number.isFinite(window) && window > 0) {
        value = { contextTokens: input + output, contextWindow: window };
      }
      break;
    }
    codexContextCache.set(key, { size: st.size, mtimeMs: st.mtimeMs, value });
    return value;
  } catch { return null; }
}

export function scanCodexSessions({ codexHome = CODEX_HOME } = {}) {
  const out = [];
  for (const { file, st } of recentFiles(codexDirs(codexHome), /^rollout-.*\.jsonl$/)) {
    const h = codexHeader(file, st); if (!h) continue;
    out.push({
      id: `codex:${h.sessionId}`, agent: 'codex', agentSessionId: h.sessionId, cwd: h.cwd, title: h.title, branch: null,
      source: h.source === 'exec' ? 'sdk' : 'terminal', status: 'idle', pendingApprovals: 0,
      createdAt: h.createdAt ?? new Date(st.birthtimeMs || st.mtimeMs).toISOString(), updatedAt: new Date(st.mtimeMs).toISOString(),
      mode: 'normal', model: null, effort: null, usage: null, file,
    });
  }
  return out;
}

export function parseCodexTranscript(file, sessionId) {
  const msgs = []; const calls = new Map(); let last = null; let i = 0;
  let text; try { text = fs.readFileSync(file, 'utf8'); } catch { return []; }
  const all = lines(text).map(parse).filter(Boolean);
  // CLI 会同时写 event_msg 与 response_item，Desktop 只写 response_item：有事件就用事件，避免重复
  const hasEvents = all.some((e) => e.type === 'event_msg' && (e.payload?.type === 'user_message' || e.payload?.type === 'agent_message'));
  const push = (m) => { msgs.push(m); last = m; return m; };
  for (const e of all) {
    const p = e.payload ?? {}; const ts = e.timestamp ?? new Date().toISOString();
    if (e.type === 'event_msg' && p.type === 'user_message') { const t = stripTags(p.message); if (t) push({ id: `u-${i++}`, sessionId, role: 'user', text: t, attachments: [], toolCalls: [], approvalId: null, createdAt: ts, streaming: false }); }
    else if (e.type === 'event_msg' && p.type === 'agent_message') { if (p.message) push({ id: `a-${i++}`, sessionId, role: 'assistant', text: p.message, attachments: [], toolCalls: [], approvalId: null, createdAt: ts, streaming: false }); }
    else if (!hasEvents && e.type === 'response_item' && p.type === 'message' && (p.role === 'user' || p.role === 'assistant')) {
      const raw = textOf(p.content);
      if (p.role === 'user' && isInjected(raw)) continue;
      const t = p.role === 'user' ? stripTags(raw) : raw;
      if (t) push({ id: `${p.role[0]}-${i++}`, sessionId, role: p.role, text: t, attachments: [], toolCalls: [], approvalId: null, createdAt: ts, streaming: false });
    }
    else if (e.type === 'response_item' && (p.type === 'function_call' || p.type === 'custom_tool_call' || p.type === 'local_shell_call')) {
      const name = p.name ?? (p.type === 'local_shell_call' ? 'shell' : 'tool');
      const raw = p.input ?? p.arguments ?? (p.action?.command ? p.action.command.join(' ') : '');
      const call = { id: p.call_id ?? p.id ?? `c-${i++}`, name, detail: String(raw).slice(0, 120), state: 'done' };
      calls.set(call.id, call);
      const host = last && last.role === 'assistant' && !last.text ? last : push({ id: `t-${i++}`, sessionId, role: 'assistant', text: '', attachments: [], toolCalls: [], approvalId: null, createdAt: ts, streaming: false });
      host.toolCalls.push(call);
    } else if (e.type === 'response_item' && (p.type === 'function_call_output' || p.type === 'custom_tool_call_output')) {
      const c = calls.get(p.call_id); if (c && /error|failed/i.test(String(p.output ?? '').slice(0, 200))) c.state = 'error';
    }
  }
  return msgs.slice(-MAX_MESSAGES);
}

/** 最近一次 Codex 会话里的 token_count.rate_limits → 额度结构。 */
export function codexRateLimits({ codexHome = CODEX_HOME } = {}) {
  for (const { file } of recentFiles(codexDirs(codexHome), /^rollout-.*\.jsonl$/).slice(0, 10)) {
    const tail = lines(readTail(file, 256 * 1024)).filter((l) => l.includes('"token_count"'));
    for (let k = tail.length - 1; k >= 0; k--) {
      const rl = parse(tail[k])?.payload?.rate_limits; if (!rl) continue;
      const limits = [];
      const label = (w) => (w?.window_minutes >= 10000 ? '本周' : w?.window_minutes >= 240 ? '当前会话（5 小时）' : `${Math.round((w?.window_minutes ?? 0) / 60)} 小时`);
      for (const [k2, w] of [['primary', rl.primary], ['secondary', rl.secondary]]) {
        if (!w || w.used_percent == null) continue;
        limits.push({ id: w.window_minutes >= 10000 ? 'weekly_all' : 'session', label: label(w), percent: Math.round(Number(w.used_percent)), resetsAt: w.resets_at ? new Date(Number(w.resets_at) * 1000).toISOString() : null, window: k2 });
      }
      if (limits.length) return { limits, file, at: fs.statSync(file).mtimeMs };
    }
  }
  return null;
}

function summarize(input = {}) {
  if (typeof input.command === 'string') return input.command;
  if (typeof input.file_path === 'string') return input.file_path;
  if (typeof input.pattern === 'string') return input.pattern;
  if (typeof input.url === 'string') return input.url;
  if (typeof input.query === 'string') return input.query;
  const s = JSON.stringify(input); return s.length > 120 ? s.slice(0, 117) + '…' : s;
}

/** 两种 Agent 合并，按更新时间倒序。 */
export function scanTerminalSessions(opts = {}) {
  return [...scanClaudeSessions(opts), ...scanCodexSessions(opts)].sort((a, b) => (a.updatedAt < b.updatedAt ? 1 : -1));
}
export function parseTranscript(session) {
  return session.agent === 'codex' ? parseCodexTranscript(session.file, session.id) : parseClaudeTranscript(session.file, session.id);
}
