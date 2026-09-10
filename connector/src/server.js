// YzVibe 连接器：HTTP REST + WebSocket（协议见 shared/protocol.md）
import http from 'node:http';
import os from 'node:os';
import fs from 'node:fs';
import path from 'node:path';
import { randomBytes } from 'node:crypto';
import { WebSocketServer, WebSocket } from 'ws';
import { Store, HOME } from './store.js';
import { Pairing, lanAddresses, pairURL, printQR } from './pairing.js';
import { startCloudflareTunnel, loadRelay, saveRelay } from './tunnel.js';
import { listDir, previewFile, resolveInside, mimeOf } from './files.js';
import { ClaudeAgent, classifyPermission } from './agents/claude.js';
import { CodexAgent } from './agents/codex.js';
import { MockAgent } from './agents/mock.js';
import { normalizeOptions, agentCapabilities } from './agents/options.js';
import { agentQuota } from './quota.js';
import { scanTerminalSessions, parseTranscript } from './transcripts.js';
import { listDirectories, makeDirectory } from './fs.js';

const VERSION = '0.1.0';

export const DEFAULT_PORT = 19876;

export async function createConnector({ port = DEFAULT_PORT, name = os.hostname(), defaultAgent = 'claude', home = HOME, log = console.log, portFallback = true, importTerminal = true, claudeHome, codexHome } = {}) {
  const store = new Store(home);
  const pairing = new Pairing();
  const internalSecret = randomBytes(16).toString('hex');
  const agents = new Map();            // sessionId → agent 实例
  const sockets = new Set();

  const deviceName = name;

  // ---------- Agent 工厂 ----------
  function agentFor(session, options = {}) {
    if (agents.has(session.id)) return agents.get(session.id);
    const kind = session.agent === 'mock' || defaultAgent === 'mock' ? 'mock' : session.agent;
    const internalURL = `http://127.0.0.1:${api.port}/internal/approval`;
    const a = kind === 'mock' ? new MockAgent({ session, store })
      : kind === 'codex' ? new CodexAgent({ session, store })
      : new ClaudeAgent({ session, store, internalURL, internalSecret, home, options });
    agents.set(session.id, a);
    return a;
  }

  // ---------- 终端会话导入 ----------
  const scanOpts = { ...(claudeHome && { claudeHome }), ...(codexHome && { codexHome }) };
  /** 终端里的会话（未被接管的），与 store 会话合并成列表。 */
  function terminalSessions() {
    if (!importTerminal) return [];
    try {
      const adopted = new Set(store.sessions.map((s) => s.agentSessionId).filter(Boolean));
      return scanTerminalSessions(scanOpts).filter((t) => !store.session(t.id) && !adopted.has(t.agentSessionId));
    } catch (e) { log(`[yzvibe] 扫描终端会话失败：${e.message}`); return []; }
  }
  function allSessions() {
    const list = [...store.listSessions(), ...terminalSessions().map(({ file, agentSessionId, ...rest }) => rest)];
    return list.sort((a, b) => (a.updatedAt < b.updatedAt ? 1 : -1));
  }
  /** 按 id 取会话；是终端会话就先接管（解析 transcript 预填历史）。 */
  function resolveSession(id) {
    const s = store.session(id); if (s || !importTerminal) return s;
    const t = scanTerminalSessions(scanOpts).find((x) => x.id === id); if (!t) return null;
    log(`[yzvibe] 接管终端会话：${t.agent} ${t.title}`);
    return store.adoptSession(t, parseTranscript(t));
  }

  // ---------- WS 广播 ----------
  store.on('event', (ev) => {
    const data = JSON.stringify(ev);
    for (const ws of sockets) if (ws.readyState === WebSocket.OPEN) ws.send(data);
  });

  // ---------- HTTP ----------
  const json = (res, status, body) => { res.writeHead(status, { 'content-type': 'application/json; charset=utf-8' }); res.end(JSON.stringify(body)); };
  const readBody = (req) => new Promise((resolve, reject) => { const chunks = []; req.on('data', (c) => chunks.push(c)); req.on('end', () => resolve(Buffer.concat(chunks))); req.on('error', reject); });
  const readJSON = async (req) => { const b = await readBody(req); try { return b.length ? JSON.parse(b) : {}; } catch { throw Object.assign(new Error('JSON 不合法'), { status: 400 }); } };
  const bearer = (req, url) => (req.headers.authorization ?? '').replace(/^Bearer\s+/i, '') || url.searchParams.get('token') || '';
  const authed = (req, url) => store.deviceByToken(bearer(req, url));

  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, `http://localhost:${port}`);
    const p = url.pathname;
    try {
      // 公开
      if (req.method === 'GET' && p === '/health') return json(res, 200, { name: deviceName, version: VERSION, agents: ['claude', 'codex', 'mock'], connectorId: store.connector.id, uptime: process.uptime() });
      if (req.method === 'POST' && p === '/pair') {
        const { token, phoneName } = await readJSON(req);
        if (!pairing.consume(token)) return json(res, 401, { error: '配对码无效或已过期，请在电脑上重新运行 npx yzvibe' });
        const d = store.addDevice(phoneName ?? '手机');
        log(`[yzvibe] 手机已配对：${d.name} (${d.id.slice(0, 8)})`);
        await announce();
        return json(res, 200, { deviceToken: d.token, deviceName, connectorId: store.connector.id, name: deviceName });
      }
      // 内部：MCP 审批桥
      if (req.method === 'POST' && p === '/internal/approval') {
        if (req.headers['x-yzvibe-secret'] !== internalSecret) return json(res, 403, { error: 'forbidden' });
        const { sessionId, toolName, input } = await readJSON(req);
        const c = classifyPermission(toolName, input);
        const decision = await store.requestApproval({ sessionId, toolName, ...c });
        // 计划被批准后 claude 进程内部已切到普通权限，这里只同步会话记录，不重启进程
        if (toolName === 'ExitPlanMode' && decision !== 'deny') { store.configureSession(sessionId, { mode: 'normal' }); agents.get(sessionId)?.configure({ mode: 'normal' }); }
        return json(res, 200, { decision });
      }
      // 以下需要设备 Token
      if (!authed(req, url)) return json(res, 401, { error: 'unauthorized' });

      if (req.method === 'GET' && p === '/agents') return json(res, 200, await agentCapabilities());
      if (req.method === 'GET' && p === '/quota') return json(res, 200, await agentQuota(url.searchParams.get('agent') ?? 'claude', { force: url.searchParams.get('force') === '1' }));
      if (req.method === 'GET' && p === '/fs/dirs') return json(res, 200, listDirectories(url.searchParams.get('path')));
      if (req.method === 'POST' && p === '/fs/mkdir') { const { parent, name } = await readJSON(req); return json(res, 201, makeDirectory(parent, name)); }
      if (req.method === 'GET' && p === '/sessions') return json(res, 200, allSessions());
      if (req.method === 'POST' && p === '/sessions') {
        const body = await readJSON(req);
        const agent = body.agent ?? defaultAgent;
        const cwd = body.cwd || os.homedir();
        try { resolveInside(cwd, ''); if (!fs.existsSync(resolveInside(cwd, '').base)) throw new Error(); } catch { return json(res, 400, { error: `工作目录不存在：${cwd}` }); }
        const title = body.firstMessage ? String(body.firstMessage).slice(0, 40) : '新会话';
        const s = store.createSession({ agent, cwd, title, ...normalizeOptions(body, agent) });
        const a = agentFor(s, { continueLast: Boolean(body.continueLast) });
        if (body.firstMessage) { store.addMessage(s.id, { role: 'user', text: body.firstMessage }); a.send(body.firstMessage).catch(() => {}); }
        return json(res, 201, store.publicSession(s));
      }
      let m;
      if ((m = p.match(/^\/sessions\/([^/]+)$/))) {
        const s = resolveSession(m[1]); if (!s) return json(res, 404, { error: 'not found' });
        if (req.method === 'GET') return json(res, 200, store.publicSession(s));
        if (req.method === 'PATCH') { configureSession(s, await readJSON(req)); return json(res, 200, store.publicSession(s)); }
        if (req.method === 'DELETE') { agents.get(s.id)?.dispose(); agents.delete(s.id); store.closeSession(s.id); return json(res, 200, { ok: true }); }
      }
      if ((m = p.match(/^\/sessions\/([^/]+)\/messages$/))) {
        const s = resolveSession(m[1]); if (!s) return json(res, 404, { error: 'not found' });
        if (req.method === 'GET') {
          const after = url.searchParams.get('after');
          const list = store.messagesOf(s.id);
          const i = after ? list.findIndex((x) => x.id === after) : -1;
          return json(res, 200, list.slice(i + 1));
        }
        if (req.method === 'POST') { const { text, attachments = [] } = await readJSON(req); await handleSend(s, text, attachments); return json(res, 202, { ok: true }); }
      }
      if ((m = p.match(/^\/sessions\/([^/]+)\/stop$/)) && req.method === 'POST') {
        const s = resolveSession(m[1]); if (!s) return json(res, 404, { error: 'not found' });
        agents.get(s.id)?.stop(); return json(res, 200, { ok: true });
      }
      if (req.method === 'GET' && p === '/approvals') return json(res, 200, store.listApprovals(url.searchParams.get('status') ?? undefined));
      if ((m = p.match(/^\/approvals\/([^/]+)$/)) && req.method === 'POST') {
        const { decision } = await readJSON(req);
        if (!['allow', 'deny', 'allow_once'].includes(decision)) return json(res, 400, { error: 'decision 不合法' });
        return json(res, store.resolveApproval(m[1], decision) ? 200 : 409, { ok: true });
      }
      // 文件
      if (p === '/files' || p === '/files/preview' || p === '/files/download') {
        const s = resolveSession(url.searchParams.get('sessionId') ?? ''); if (!s) return json(res, 400, { error: '需要 sessionId' });
        const rel = url.searchParams.get('path') ?? '';
        if (p === '/files') return json(res, 200, listDir(s.cwd, rel));
        if (p === '/files/preview') { const { mime, body } = previewFile(s.cwd, rel); res.writeHead(200, { 'content-type': mime }); return res.end(body); }
        const { target } = resolveInside(s.cwd, rel);
        res.writeHead(200, { 'content-type': mimeOf(target), 'content-disposition': `attachment; filename="${encodeURIComponent(path.basename(target))}"` });
        return fs.createReadStream(target).pipe(res);
      }
      // 上传（二进制 body + X-Filename）
      if (req.method === 'POST' && p === '/uploads') {
        const buf = await readBody(req);
        if (buf.length > 20 * 1024 * 1024) return json(res, 413, { error: '文件过大' });
        const id = store.addUpload(decodeURIComponent(req.headers['x-filename'] ?? 'upload.bin'), req.headers['content-type'] ?? 'application/octet-stream', buf);
        return json(res, 201, { id, url: `/uploads/${id}` });
      }
      if ((m = p.match(/^\/uploads\/([^/]+)$/)) && req.method === 'GET') {
        const u = store.upload(m[1]); if (!u) return json(res, 404, { error: 'not found' });
        res.writeHead(200, { 'content-type': u.mime }); return fs.createReadStream(u.path).pipe(res);
      }
      json(res, 404, { error: 'not found' });
    } catch (e) {
      json(res, e.status ?? 500, { error: e.message });
    }
  });

  /** 手机改了 mode / model / effort：写入会话并通知已存在的 Agent 实例。 */
  function configureSession(s, body) {
    const patch = normalizeOptions(body, s.agent);
    if (store.configureSession(s.id, patch)) agents.get(s.id)?.configure(patch);
  }

  async function handleSend(s, text, attachments) {
    if (!text?.trim() && !attachments.length) return;
    store.addMessage(s.id, { role: 'user', text: text ?? '', attachments });
    if (s.status === 'closed') store.setStatus(s.id, 'idle');
    await agentFor(s).send(text ?? '', attachments);
  }

  // ---------- WebSocket ----------
  const wss = new WebSocketServer({ noServer: true });
  server.on('upgrade', (req, socket, head) => {
    const url = new URL(req.url, `http://localhost:${port}`);
    if (url.pathname !== '/ws' || !authed(req, url)) { socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n'); socket.destroy(); return; }
    wss.handleUpgrade(req, socket, head, (ws) => {
      sockets.add(ws);
      ws.on('close', () => sockets.delete(ws));
      ws.on('message', async (raw) => {
        let msg; try { msg = JSON.parse(raw); } catch { return; }
        const s = msg.sessionId ? resolveSession(msg.sessionId) : null;
        try {
          switch (msg.type) {
            case 'message.send': if (s) await handleSend(s, msg.text, msg.attachments ?? []); break;
            case 'session.stop': if (s) agents.get(s.id)?.stop(); break;
            case 'session.resume': if (s && s.status === 'closed') store.setStatus(s.id, 'idle'); break;
            case 'session.configure': if (s) configureSession(s, msg); break;
            case 'approval.respond': store.resolveApproval(msg.approvalId, msg.decision); break;
            case 'ping': ws.send(JSON.stringify({ type: 'pong' })); break;
            default: break;
          }
        } catch (e) { ws.send(JSON.stringify({ type: 'error', message: e.message })); }
      });
    });
  });

  let announce = async () => {};
  /** 监听 port；被占用时（EADDRINUSE）自动向后尝试最多 20 个端口，返回实际端口。 */
  const listenWithFallback = () => new Promise((resolve, reject) => {
    const tryPort = (p, left) => {
      const onError = (e) => {
        server.removeListener('error', onError);
        if (e.code === 'EADDRINUSE' && portFallback && left > 0 && p !== 0) { log(`[yzvibe] 端口 ${p} 已被占用，改试 ${p + 1}`); tryPort(p + 1, left - 1); }
        else reject(e);
      };
      server.once('error', onError);
      server.listen(p, '0.0.0.0', () => { server.removeListener('error', onError); api.port = server.address().port; resolve(api.port); });
    };
    tryPort(port, 20);
  });
  const api = {
    store, pairing, server, port,
    listen: listenWithFallback,
    close: () => new Promise((resolve) => { for (const a of agents.values()) a.dispose(); for (const ws of sockets) ws.close(); wss.close(); server.close(() => resolve()); }),
    setAnnounce: (fn) => { announce = fn; },
  };
  return api;
}

/** CLI 入口：起服务、决定访问方式、打印二维码。 */
export async function startConnector(opts) {
  const c = await createConnector(opts);
  await c.listen();
  const name = opts.name ?? os.hostname();
  let host, mode, tunnelChild;

  if (opts.access === 'local') { host = lanAddresses()[0]; mode = 'local'; }
  else if (/^https?:\/\//.test(opts.access)) { host = opts.access; mode = 'relay'; saveRelay(host); }
  else if (opts.access && opts.access !== 'remote') { host = opts.access; mode = opts.access.startsWith('100.') ? 'tailscale' : 'local'; }
  else {
    const relay = !opts.force && loadRelay();
    if (relay) { host = relay; mode = 'relay'; console.log(`[yzvibe] 复用已保存的 relay：${relay}（--force 可换新）`); }
    else {
      process.stdout.write('[yzvibe] 正在启动 Cloudflare Tunnel… ');
      try { const t = await startCloudflareTunnel(c.port); host = t.url; mode = 'tunnel'; tunnelChild = t.child; console.log(host); }
      catch (e) { console.log(`失败（${e.message}），退回局域网`); host = lanAddresses()[0]; mode = 'local'; }
    }
  }
  if (!host) { host = '127.0.0.1'; mode = 'local'; }

  const announce = async () => {
    const url = pairURL({ host, port: c.port, token: c.pairing.token, mode, name });
    console.log(`\nYzVibe 连接器 v${VERSION} · ${name} · 端口 ${c.port} · 模式 ${mode}${opts.defaultAgent === 'mock' ? ' · Mock Agent' : ''}`);
    console.log(`用手机 YzVibe App 扫描下面的二维码（10 分钟内有效，一次性）：\n`);
    await printQR(url);
    if (mode === 'local') console.log(`提示：手机需与电脑在同一 Wi-Fi；远程访问请直接运行 npx yzvibe（Cloudflare Tunnel）。`);
  };
  c.setAnnounce(announce);
  await announce();

  const shutdown = async () => { console.log('\n[yzvibe] 正在退出…'); tunnelChild?.kill(); await c.close(); process.exit(0); };
  process.on('SIGINT', shutdown); process.on('SIGTERM', shutdown);
  return c;
}
