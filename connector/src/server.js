// YzVibe 连接器：HTTP REST + WebSocket（协议见 shared/protocol.md）
import http from 'node:http';
import os from 'node:os';
import fs from 'node:fs';
import path from 'node:path';
import { randomBytes } from 'node:crypto';
import { WebSocketServer, WebSocket } from 'ws';
import { Store, HOME, describeRule } from './store.js';
import { Pairing, lanAddresses, pairURL, pairLink, pairConfig, pairPageHTML, printQR } from './pairing.js';
import { startCloudflareTunnel, retryTunnel, loadRelay, saveRelay } from './tunnel.js';
import { listDir, previewFile, resolveInside, resolveReadable, statFile, mimeOf } from './files.js';
import { ClaudeAgent, classifyPermission } from './agents/claude.js';
import { CodexAgent } from './agents/codex.js';
import { MockAgent } from './agents/mock.js';
import { normalizeOptions, agentCapabilities } from './agents/options.js';
import { agentQuota } from './quota.js';
import { scanTerminalSessions, parseTranscript } from './transcripts.js';
import { listDirectories, makeDirectory } from './fs.js';
import { writeDaemonInfo, clearDaemonInfo } from './daemon.js';
import { Rules } from './rules.js';
import { Pusher } from './push.js';
import { startCleanupLoop } from './cleanup.js';
import { collectEndpoints, advertiseBonjour } from './endpoints.js';
import { workingDiff, headCommit } from './git.js';
import { sessionCommands } from './commands.js';

export const VERSION = '0.1.0';

export const DEFAULT_PORT = 19876;

export async function createConnector({ port = DEFAULT_PORT, name = os.hostname(), defaultAgent = 'claude', home = HOME, log = console.log, portFallback = true, importTerminal = true, claudeHome, codexHome } = {}) {
  const store = new Store(home);
  const rules = new Rules(home);
  store.rules = rules;
  const pairing = new Pairing();
  const internalSecret = randomBytes(16).toString('hex');
  const agents = new Map();            // sessionId → agent 实例
  const sockets = new Set();           // 每个 ws 上挂了 ws.deviceId

  const deviceName = name;
  const pusher = new Pusher({
    home, log,
    onInvalid: (deviceId, { keep, environment, activityToken, drop }) => {
      if (drop && activityToken) { store.dropLiveActivity(activityToken); return; }
      const d = store.devices.find((x) => x.id === deviceId);
      store.setDevicePush(deviceId, keep && d?.push ? { ...d.push, environment } : null);
    },
  });
  const stopCleanup = startCleanupLoop(store, { log });

  /** 当前配对信息（配对码过期会自动换新）：{ token, expiresAt, url, link, config }。access 未定时 link/url 为 null。 */
  function currentPairing() {
    const token = pairing.current();
    const expiresAt = new Date(pairing.expiresAt).toISOString();
    const { host, mode } = api.access;
    if (!host) return { token, expiresAt, url: null, link: null, config: null };
    const opts = { host, port: api.port, token, mode, name: deviceName };
    return { token, expiresAt, url: pairURL(opts), link: pairLink(opts),
             config: pairConfig({ ...opts, expiresAt, connectorId: store.connector.id, version: VERSION, endpoints: api.endpoints() }) };
  }

  // ---------- Agent 工厂 ----------
  function agentFor(session, options = {}) {
    if (agents.has(session.id)) return agents.get(session.id);
    const kind = session.agent === 'mock' || defaultAgent === 'mock' ? 'mock' : session.agent;
    const internalURL = `http://127.0.0.1:${api.port}/internal/approval`;
    const a = kind === 'mock' ? new MockAgent({ session, store })
      : kind === 'codex' ? new CodexAgent({ session, store })
      : new ClaudeAgent({ session, store, internalURL, internalSecret, home, log, options });
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
    return list.filter((s) => !store.isHidden(s.id)).sort((a, b) => (a.updatedAt < b.updatedAt ? 1 : -1));
  }
  /** 按 id 取会话；是终端会话就先接管（解析 transcript 预填历史）。 */
  function resolveSession(id) {
    const s = store.session(id); if (s) return s;
    if (!importTerminal || store.isHidden(id)) return null;
    const t = scanTerminalSessions(scanOpts).find((x) => x.id === id); if (!t) return null;
    log(`[yzvibe] 接管终端会话：${t.agent} ${t.title}`);
    return store.adoptSession(t, parseTranscript(t));
  }

  // ---------- WS 广播 ----------
  store.on('event', (ev) => {
    const data = JSON.stringify(ev);
    for (const ws of sockets) if (ws.readyState === WebSocket.OPEN) ws.send(data);
  });

  // ---------- 远程推送 ----------
  // App 被 iOS 挂起后 WebSocket 必然断开，只有 APNs 能叫醒它——这是「离开电脑也能审批」成立的前提。
  const phoneOnline = () => [...sockets].some((w) => w.readyState === WebSocket.OPEN);
  const pendingCount = () => store.listApprovals('pending').length;
  const RISK_LABEL = { high: '高风险', medium: '中风险', low: '低风险' };
  store.on('event', (ev) => {
    if (!pusher.ready) return;
    try {
      if (ev.type === 'approval.requested') {
        const s = store.session(ev.sessionId);
        pusher.send(store.devices, {
          title: `需要批准 · ${RISK_LABEL[ev.risk] ?? ''}`.trim(),
          body: `${s?.title ? s.title + ' · ' : ''}${String(ev.summary ?? '').slice(0, 160)}`,
          category: 'APPROVAL', threadId: ev.sessionId, collapseId: `approval-${ev.approvalId}`,
          badge: pendingCount(), ttlSeconds: 600,
          data: { kind: 'approval', approvalId: ev.approvalId, sessionId: ev.sessionId, connector: deviceName },
        }).catch((e) => log(`[yzvibe] 推送异常：${e.message}`));
        pushLiveActivity(ev.sessionId).catch(() => {});
      } else if (ev.type === 'approval.resolved') {
        pusher.send(store.devices, { silent: true, badge: pendingCount(), data: { kind: 'approval.resolved', approvalId: ev.approvalId } }).catch(() => {});
      } else if (ev.type === 'session.status' || ev.type === 'session.updated') {
        pushLiveActivity(ev.sessionId ?? ev.session?.id).catch(() => {});
      } else if (ev.type === 'message.done') {
        pushLiveActivity(ev.sessionId).catch(() => {});
        if (phoneOnline()) return;                       // 手机还连着，App 自己会显示
        const s = store.session(ev.sessionId); if (!s) return;
        const text = (store.messagesOf(ev.sessionId).find((m) => m.id === ev.messageId)?.text ?? '').trim();
        if (!text) return;
        pusher.send(store.devices, {
          title: `${s.agent === 'codex' ? 'Codex' : 'Claude'} 回复完成`, body: `${s.title}\n${text.slice(0, 150)}`,
          level: 'active', threadId: ev.sessionId, collapseId: `reply-${ev.sessionId}`, badge: pendingCount(),
          data: { kind: 'reply', sessionId: ev.sessionId, messageId: ev.messageId },
        }).catch(() => {});
      }
    } catch (e) { log(`[yzvibe] 推送出错：${e.message}`); }
  });

  /**
   * 把会话状态推到锁屏 / 灵动岛。手机被挂起时这是唯一能更新它的路径。
   * ContentState 的字段要和 iOS 端 SessionActivityAttributes.ContentState 完全对上，
   * 其中 Date 用 Swift 的默认编码（自 2001-01-01 起的秒数）。
   */
  async function pushLiveActivity(sessionId) {
    if (!pusher.ready || !sessionId) return;
    const targets = store.liveActivitiesFor(sessionId);
    if (!targets.length) return;
    const s = store.session(sessionId); if (!s) return;
    const pending = store.listApprovals('pending').filter((a) => a.sessionId === sessionId);
    const running = s.status === 'running';
    const idle = !running && !pending.length && !(s.queue?.length);

    const msgs = store.messagesOf(sessionId);
    const lastTool = [...msgs].reverse().flatMap((m) => m.toolCalls ?? []).find((t) => t.state === 'running');
    const lastText = [...msgs].reverse().find((m) => m.role === 'assistant' && m.text)?.text ?? '';
    const headline = pending.length ? `等你批准：${pending[0].summary}`
      : running ? (lastTool ? `正在 ${lastTool.name}：${lastTool.detail}` : '正在处理…')
      : s.status === 'error' ? '出错了，去看看'
      : lastText.slice(0, 80) || '已完成';

    const ctx = s.usage?.turn;
    const state = {
      status: s.status,
      headline,
      pendingApprovals: pending.length,
      queued: s.queue?.length ?? 0,
      contextPercent: ctx?.contextTokens && ctx?.contextWindow ? Math.round((ctx.contextTokens / ctx.contextWindow) * 100) : null,
      updatedAt: Math.floor(Date.now() / 1000) - 978307200,      // Swift Date 的默认编码
    };
    await pusher.sendLiveActivity(targets, { state, event: idle ? 'end' : 'update', dismissSeconds: idle ? 30 : 0 }).catch(() => {});
    if (idle) for (const t of targets) store.dropLiveActivity(t.token);
  }

  /**
   * 地址变了（重启、Cloudflare 临时隧道换地址）就静默推一条给所有手机。
   * 没有这一步，隧道每次重开手机都得重新扫码——这是最常见的一个使用障碍。
   */
  async function announceEndpoints(reason = 'startup') {
    const endpoints = api.endpoints();
    if (!pusher.ready || !store.devices.some((d) => d.push?.token)) return;
    await pusher.send(store.devices, {
      silent: true,
      data: { kind: 'endpoint', connectorId: store.connector.id, name: deviceName, host: api.access.host, port: api.port, mode: api.access.mode, endpoints, reason },
    }).catch(() => {});
    log(`[yzvibe] 已把新地址推给已配对的手机（${reason}）：${endpoints[0]}`);
  }

  /** 撤销设备时把它的连接断掉。 */
  store.on('device.removed', (deviceId) => {
    for (const ws of sockets) if (ws.deviceId === deviceId) { try { ws.close(4001, 'device revoked'); } catch {} }
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
      if (req.method === 'GET' && p === '/health') return json(res, 200, { name: deviceName, version: VERSION, agents: ['claude', 'codex', 'mock'], connectorId: store.connector.id, uptime: process.uptime(), endpoints: api.endpoints() });
      // 手机浏览器打开的落地页 / 配置：/pair?token= 与 /pair.json?token=（一次性配对码本身就是凭据，不消费它）
      if (req.method === 'GET' && (p === '/pair' || p === '/pair.json')) {
        const given = url.searchParams.get('token') ?? '';
        if (!given || given !== pairing.token || pairing.expired) {
          const msg = '配对码无效或已过期，请在电脑上运行 yzvibe qr 重新出示。';
          if (p === '/pair.json') return json(res, 410, { error: msg });
          res.writeHead(410, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' });
          return res.end(`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><body style="font:16px/1.6 -apple-system,sans-serif;padding:40px 24px;color:#2b2622"><h2>链接已失效</h2><p>${msg}</p>`);
        }
        const { config, expiresAt } = currentPairing();
        if (p === '/pair.json') { res.writeHead(200, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' }); return res.end(JSON.stringify(config, null, 2)); }
        res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' });
        return res.end(pairPageHTML(config, { minutesLeft: Math.max(1, Math.round((new Date(expiresAt) - Date.now()) / 60000)) }));
      }
      if (req.method === 'POST' && p === '/pair') {
        const { token, phoneName } = await readJSON(req);
        if (!pairing.consume(token)) return json(res, 401, { error: '配对码无效或已过期，请在电脑上运行 yzvibe qr 重新出示' });
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
        const decision = await store.requestApproval({ sessionId, toolName, agent: store.session(sessionId)?.agent ?? 'claude', ...c });
        // 计划被批准后 claude 进程内部已切到普通权限，这里只同步会话记录，不重启进程
        if (toolName === 'ExitPlanMode' && decision !== 'deny') { store.configureSession(sessionId, { mode: 'normal' }); agents.get(sessionId)?.configure({ mode: 'normal' }); }
        return json(res, 200, { decision });
      }
      // 内部：本机 CLI（yzvibe status / qr）取当前配对码与统计；过期的配对码在这里自动换新
      if (req.method === 'GET' && p === '/internal/status') {
        if (req.headers['x-yzvibe-secret'] !== internalSecret) return json(res, 403, { error: 'forbidden' });
        const sessions = store.sessions;
        return json(res, 200, {
          pid: process.pid, name: deviceName, version: VERSION, port: api.port, uptime: process.uptime(), ...api.access,
          pairing: currentPairing(),
          endpoints: api.endpoints(),
          push: pusher.status(store.devices),
          stats: { devices: store.devices.length, sessions: sessions.filter((x) => x.status !== 'closed').length, running: sessions.filter((x) => x.status === 'running').length, pendingApprovals: store.listApprovals('pending').length, rules: rules.all().length },
        });
      }
      // 内部：本机 CLI 管理已配对的手机（yzvibe devices / revoke）与推送自检（yzvibe push）
      if (p === '/internal/devices' || p.startsWith('/internal/devices/') || p === '/internal/push-test') {
        if (req.headers['x-yzvibe-secret'] !== internalSecret) return json(res, 403, { error: 'forbidden' });
        if (req.method === 'GET' && p === '/internal/devices') return json(res, 200, store.listDevices());
        const dm = p.match(/^\/internal\/devices\/([^/]+)$/);
        if (dm && req.method === 'DELETE') {
          const target = store.devices.find((d) => d.id === dm[1] || d.id.startsWith(dm[1]) || d.name === dm[1]);
          if (!target) return json(res, 404, { error: 'not found' });
          store.removeDevice(target.id);
          log(`[yzvibe] 已撤销手机：${target.name} (${target.id.slice(0, 8)})`);
          return json(res, 200, { ok: true, id: target.id, name: target.name });
        }
        if (req.method === 'POST' && p === '/internal/push-test') {
          pusher.reload();
          if (!pusher.ready) return json(res, 200, { ok: false, status: pusher.status(store.devices) });
          const results = await pusher.send(store.devices, { title: 'YzVibe 推送自检', body: `来自 ${deviceName}，收到这条说明推送已经打通。`, level: 'active', collapseId: 'push-test', data: { kind: 'test' } });
          return json(res, 200, { ok: results.length > 0 && results.every((r) => r?.ok), results, status: pusher.status(store.devices) });
        }
      }
      // 以下需要设备 Token
      const authDevice = authed(req, url);
      if (!authDevice) return json(res, 401, { error: 'unauthorized' });

      let m;
      if (req.method === 'GET' && p === '/agents') return json(res, 200, await agentCapabilities());
      // 手机注册 / 注销 APNs token
      if (p === '/devices/push') {
        if (req.method === 'POST') {
          const { token, environment, bundleId } = await readJSON(req);
          if (!/^[0-9a-fA-F]{40,200}$/.test(String(token ?? ''))) return json(res, 400, { error: '推送 token 不合法' });
          store.setDevicePush(authDevice.id, { token, environment: environment === 'production' ? 'production' : 'sandbox', bundleId });
          log(`[yzvibe] ${authDevice.name} 已注册推送（${environment ?? 'sandbox'}）`);
          return json(res, 200, { ok: true, push: pusher.status(store.devices) });
        }
        if (req.method === 'DELETE') { store.setDevicePush(authDevice.id, null); return json(res, 200, { ok: true }); }
      }
      // 手机为某个会话开了锁屏 / 灵动岛活动，把 token 交过来，之后由电脑直接推更新
      if (req.method === 'POST' && p === '/devices/live-activity') {
        const { sessionId, token, environment } = await readJSON(req);
        if (!sessionId || !/^[0-9a-fA-F]{40,200}$/.test(String(token ?? ''))) return json(res, 400, { error: '参数不合法' });
        store.setLiveActivity(authDevice.id, sessionId, { token, environment });
        log(`[yzvibe] ${authDevice.name} 为会话 ${String(sessionId).slice(0, 8)} 开了实时活动`);
        pushLiveActivity(sessionId).catch(() => {});
        return json(res, 200, { ok: true });
      }
      // 一次性把会话 / 待审批 / 能力表 / 规则拿全：App 回到前台补数据用，省往返
      if (req.method === 'GET' && p === '/sync') {
        return json(res, 200, {
          serverTime: new Date().toISOString(),
          sessions: allSessions(),
          approvals: store.listApprovals('pending'),
          agents: await agentCapabilities(),
          rules: rules.all().map((r) => ({ ...r, description: describeRule(r) })),
          push: pusher.status(store.devices),
          hiddenSessions: store.listHidden().length,
        });
      }
      // 审批规则
      if (req.method === 'GET' && p === '/rules') return json(res, 200, rules.all(url.searchParams.get('sessionId') ?? null).map((r) => ({ ...r, description: describeRule(r) })));
      if (req.method === 'POST' && p === '/rules') { const r = rules.add(await readJSON(req)); return json(res, 201, { ...r, description: describeRule(r) }); }
      if ((m = p.match(/^\/rules\/([^/]+)$/)) && req.method === 'DELETE') return json(res, rules.remove(m[1]) ? 200 : 404, { ok: true });
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
        store.setBaseline(s.id, await headCommit(cwd));
        const a = agentFor(s, { continueLast: Boolean(body.continueLast) });
        if (body.firstMessage) { store.addMessage(s.id, { role: 'user', text: body.firstMessage }); a.send(body.firstMessage).catch(() => {}); }
        return json(res, 201, store.publicSession(s));
      }
      // 手机上删掉的会话：连终端扫描出来的也要记住别再出现（transcript 文件本身不动）
      if (p === '/sessions/hidden') {
        if (req.method === 'GET') return json(res, 200, { ids: store.listHidden() });
        if (req.method === 'DELETE') return json(res, 200, { restored: store.restoreHidden(null) });
      }
      if ((m = p.match(/^\/sessions\/hidden\/([^/]+)$/)) && req.method === 'DELETE') {
        return json(res, 200, { restored: store.restoreHidden(m[1]) });
      }
      if ((m = p.match(/^\/sessions\/([^/]+)$/))) {
        // 删除不用先接管终端会话：直接按 id 标记隐藏即可
        if (req.method === 'DELETE') {
          const id = m[1];
          agents.get(id)?.dispose(); agents.delete(id);
          store.deleteSession(id);
          return json(res, 200, { ok: true });
        }
        const s = resolveSession(m[1]); if (!s) return json(res, 404, { error: 'not found' });
        if (req.method === 'GET') return json(res, 200, store.publicSession(s));
        if (req.method === 'PATCH') { configureSession(s, await readJSON(req)); return json(res, 200, store.publicSession(s)); }
      }
      if ((m = p.match(/^\/sessions\/([^/]+)\/close$/)) && req.method === 'POST') {
        const s = resolveSession(m[1]); if (!s) return json(res, 404, { error: 'not found' });
        agents.get(s.id)?.dispose(); agents.delete(s.id); store.closeSession(s.id);
        return json(res, 200, store.publicSession(s));
      }
      if ((m = p.match(/^\/sessions\/([^/]+)\/messages$/))) {
        const s = resolveSession(m[1]); if (!s) return json(res, 404, { error: 'not found' });
        if (req.method === 'GET') {
          const after = url.searchParams.get('after');
          const list = store.messagesOf(s.id);
          const i = after ? list.findIndex((x) => x.id === after) : -1;
          return json(res, 200, list.slice(i + 1));
        }
        if (req.method === 'POST') {
          const { text, attachments = [], mode = 'auto' } = await readJSON(req);
          const r = await handleSend(s, text, attachments, mode);
          return json(res, 202, { ok: true, ...r });
        }
      }
      // 这个目录现在有哪些改动。scope=session 时跟会话开始时的 commit 比
      if ((m = p.match(/^\/sessions\/([^/]+)\/diff$/)) && req.method === 'GET') {
        const s = resolveSession(m[1]); if (!s) return json(res, 404, { error: 'not found' });
        const base = url.searchParams.get('scope') === 'session' ? (s.baseCommit ?? null) : null;
        return json(res, 200, await workingDiff(s.cwd, { base }));
      }
      // 这个会话里能用的斜杠命令与 skill
      if ((m = p.match(/^\/sessions\/([^/]+)\/commands$/)) && req.method === 'GET') {
        const s = resolveSession(m[1]); if (!s) return json(res, 404, { error: 'not found' });
        return json(res, 200, sessionCommands(s.agent, s.cwd, { session: s, ...(claudeHome && { claudeHome }), ...(codexHome && { codexHome }) }));
      }
      if ((m = p.match(/^\/sessions\/([^/]+)\/queue\/resume$/)) && req.method === 'POST') {
        const s = resolveSession(m[1]); if (!s) return json(res, 404, { error: 'not found' });
        store.resumeQueue(s.id);
        if (s.status === 'error') store.setStatus(s.id, 'idle');
        void drainQueue(s.id);
        return json(res, 200, store.publicSession(s));
      }
      if ((m = p.match(/^\/sessions\/([^/]+)\/queue\/([^/]+)$/)) && req.method === 'DELETE') {
        const s = resolveSession(m[1]); if (!s) return json(res, 404, { error: 'not found' });
        return json(res, store.cancelQueued(s.id, m[2]) ? 200 : 404, { ok: true });
      }
      if ((m = p.match(/^\/sessions\/([^/]+)\/stop$/)) && req.method === 'POST') {
        const s = resolveSession(m[1]); if (!s) return json(res, 404, { error: 'not found' });
        store.pauseQueue(s.id); agents.get(s.id)?.stop(); return json(res, 200, { ok: true });
      }
      if (req.method === 'GET' && p === '/approvals') return json(res, 200, store.listApprovals(url.searchParams.get('status') ?? undefined));
      if ((m = p.match(/^\/approvals\/([^/]+)$/)) && req.method === 'POST') {
        const { decision, remember } = await readJSON(req);
        if (!['allow', 'deny', 'allow_once'].includes(decision)) return json(res, 400, { error: 'decision 不合法' });
        return json(res, store.resolveApproval(m[1], decision, 'phone', remember ?? null) ? 200 : 409, { ok: true });
      }
      // 文件
      if (p === '/files' || p === '/files/preview' || p === '/files/download' || p === '/files/stat') {
        const s = resolveSession(url.searchParams.get('sessionId') ?? ''); if (!s) return json(res, 400, { error: '需要 sessionId' });
        const rel = url.searchParams.get('path') ?? '';
        if (p === '/files') return json(res, 200, listDir(s.cwd, rel));
        if (p === '/files/stat') return json(res, 200, statFile(s.cwd, rel));
        if (p === '/files/preview') { const { mime, body } = previewFile(s.cwd, rel); res.writeHead(200, { 'content-type': mime }); return res.end(body); }
        const { target } = resolveReadable(s.cwd, rel);
        res.writeHead(200, { 'content-type': mimeOf(target), 'content-length': fs.statSync(target).size, 'content-disposition': `attachment; filename="${encodeURIComponent(path.basename(target))}"` });
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

  /** 会话是不是正忙（忙的时候再发消息默认排队，而不是丢掉或打断）。 */
  const busy = (s) => s.status === 'running' || s.status === 'waiting_approval';

  /**
   * @param mode 'auto'（默认，忙就排队）| 'queue'（强制排队）| 'now'（插到队首并打断当前轮）
   * @returns { queued: boolean, item? }
   */
  async function handleSend(s, text, attachments = [], mode = 'auto') {
    if (!text?.trim() && !attachments.length) return { queued: false };
    if (s.status === 'closed') store.setStatus(s.id, 'idle');

    if ((busy(s) || s.queuePaused || s.queue?.length || mode === 'queue') && mode !== 'never') {
      const front = mode === 'now';
      const item = store.enqueue(s.id, { text: text ?? '', attachments }, { front });
      if (front && !s.queuePaused) agents.get(s.id)?.stop();     // 打断当前轮，结束后 drainQueue 会立刻把它发出去
      if (!busy(s) && !s.queuePaused) void drainQueue(s.id);
      return { queued: true, item };
    }
    store.addMessage(s.id, { role: 'user', text: text ?? '', attachments });
    await agentFor(s).send(text ?? '', attachments);
    return { queued: false };
  }

  // 出队后才崩溃会丢失消息：先持久化 dispatching，交给 Agent 后再移除。
  let closing = false;
  const draining = new Set();
  async function drainQueue(sessionId) {
    const s = store.session(sessionId);
    if (closing || !s?.queue?.length || s.queuePaused || s.status !== 'idle' || draining.has(s.id)) return;
    const item = s.queue[0];
    if (item.deliveryState !== 'queued') return;
    draining.add(s.id);
    store.markQueued(s.id, item.id, 'dispatching');
    try {
      await handleSend(s, item.text, item.attachments, 'never');
      store.cancelQueued(s.id, item.id);
    } catch (e) {
      store.markQueued(s.id, item.id, 'uncertain');
      store.pauseQueue(s.id);
      store.addMessage(s.id, { role: 'system', text: `排队消息发送结果待确认：${e.message}` });
      store.setStatus(s.id, 'error');
    } finally {
      draining.delete(s.id);
      if (s.status === 'idle' && !s.queuePaused && s.queue.length) setImmediate(() => void drainQueue(s.id));
    }
  }
  store.on('event', (ev) => {
    if (ev.type !== 'session.status') return;
    if (ev.status === 'error' || ev.status === 'closed') store.pauseQueue(ev.sessionId);
    if (ev.status === 'idle') setImmediate(() => void drainQueue(ev.sessionId));
  });

  // ---------- WebSocket ----------
  const wss = new WebSocketServer({ noServer: true });
  server.on('upgrade', (req, socket, head) => {
    const url = new URL(req.url, `http://localhost:${port}`);
    const wsDevice = authed(req, url);
    if (url.pathname !== '/ws' || !wsDevice) { socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n'); socket.destroy(); return; }
    wss.handleUpgrade(req, socket, head, (ws) => {
      ws.deviceId = wsDevice.id;
      sockets.add(ws);
      ws.on('close', () => sockets.delete(ws));
      ws.on('message', async (raw) => {
        let msg; try { msg = JSON.parse(raw); } catch { return; }
        const s = msg.sessionId ? resolveSession(msg.sessionId) : null;
        try {
          switch (msg.type) {
            case 'message.send': if (s) await handleSend(s, msg.text, msg.attachments ?? [], msg.mode ?? 'auto'); break;
            case 'message.cancel': if (s && msg.itemId) store.cancelQueued(s.id, msg.itemId); break;
            case 'session.stop': if (s) { store.pauseQueue(s.id); agents.get(s.id)?.stop(); } break;
            case 'session.resume': if (s && s.status === 'closed') store.setStatus(s.id, 'idle'); break;
            case 'session.configure': if (s) configureSession(s, msg); break;
            case 'approval.respond': store.resolveApproval(msg.approvalId, msg.decision, 'phone', msg.remember ?? null); break;
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
    store, pairing, server, port, internalSecret, announceEndpoints,
    access: { host: null, mode: null },   // startConnector 决定后填入，供 /internal/status 生成配对链接
    endpoints: () => collectEndpoints({ host: api.access.host, port: api.port, mode: api.access.mode }),
    listen: listenWithFallback,
    rules, pusher,
    close: () => new Promise((resolve) => { closing = true; stopCleanup(); pusher.close(); api.stopBonjour?.(); for (const a of agents.values()) a.dispose(); for (const ws of sockets) ws.close(); wss.close(); server.close(() => resolve()); }),
    setAnnounce: (fn) => { announce = fn; },
  };
  return api;
}

/** 清掉上次异常退出留下的每会话 MCP 配置（正常退出时 dispose 会删）。 */
function cleanStaleMcpConfigs(home) {
  try { for (const f of fs.readdirSync(home)) if (/^mcp-.*\.json$/.test(f)) fs.unlinkSync(path.join(home, f)); } catch {}
}

/** CLI 入口：起服务、决定访问方式、打印二维码；后台模式下把实例信息写到 ~/.yzvibe/daemon.json。 */
export async function startConnector(opts) {
  const daemon = Boolean(process.env.YZVIBE_DAEMON);
  cleanStaleMcpConfigs(opts.home ?? HOME);
  const c = await createConnector(opts);
  await c.listen();
  const name = opts.name ?? os.hostname();
  let host, mode, tunnelChild, stopping = false;

  const startedAt = new Date().toISOString();
  const saveDaemonInfo = () => writeDaemonInfo({ pid: process.pid, port: c.port, host, mode, name, agent: opts.defaultAgent, secret: c.internalSecret, flags: opts.flags ?? [], managed: process.env.YZVIBE_MANAGED ?? null, startedAt, version: VERSION });

  /** 起 Cloudflare Tunnel；进程退出或隧道被注销时持续重试（临时地址会变）。 */
  const openTunnel = async () => {
    const t = await startCloudflareTunnel(c.port);
    if (stopping) { t.child.kill(); return null; }
    tunnelChild = t.child;
    t.child.on('exit', async (code) => {
      if (stopping) return;
      console.log(`[yzvibe] Cloudflare Tunnel 断开（退出码 ${code}），5 秒后重连…`);
      try {
        const recovered = await retryTunnel(openTunnel, { stopped: () => stopping });
        if (!recovered || stopping) return;
        host = recovered; c.access.host = host; saveDaemonInfo();
        console.log(`[yzvibe] Tunnel 已重连：${host}`);
        await c.announceEndpoints('tunnel-reconnect');    // 尝试通过推送更新手机地址；静默推送不保证送达
        await announce();
      }
      catch (e) { console.log(`[yzvibe] Tunnel 重连失败：${e.message}；可用 yzvibe restart 重试`); }
    });
    return t.url;
  };

  if (opts.access === 'local') { host = lanAddresses()[0]; mode = 'local'; }
  else if (/^https?:\/\//.test(opts.access)) { host = opts.access; mode = 'relay'; saveRelay(host); }
  else if (opts.access && opts.access !== 'remote') { host = opts.access; mode = opts.access.startsWith('100.') ? 'tailscale' : 'local'; }
  else {
    const relay = !opts.force && loadRelay();
    if (relay) { host = relay; mode = 'relay'; console.log(`[yzvibe] 复用已保存的 relay：${relay}（--force 可换新）`); }
    else {
      process.stdout.write('[yzvibe] 正在启动 Cloudflare Tunnel… ');
      try { host = await openTunnel(); mode = 'tunnel'; console.log(host); }
      catch (e) { console.log(`失败（${e.message}），退回局域网`); host = lanAddresses()[0]; mode = 'local'; }
    }
  }
  if (!host) { host = '127.0.0.1'; mode = 'local'; }
  c.access = { host, mode };

  const announce = async () => {
    const url = pairURL({ host, port: c.port, token: c.pairing.current(), mode, name });
    console.log(`\nYzVibe 连接器 v${VERSION} · ${name} · 端口 ${c.port} · 模式 ${mode}${opts.defaultAgent === 'mock' ? ' · Mock Agent' : ''}`);
    if (daemon) { console.log(`配对链接（10 分钟内有效，一次性；终端里运行 yzvibe qr 显示二维码）：${url}\n`); return; }
    console.log(`用手机 YzVibe App 扫描下面的二维码（10 分钟内有效，一次性）：\n`);
    await printQR(url);
    if (mode === 'local') console.log(`提示：手机需与电脑在同一 Wi-Fi；远程访问请直接运行 npx yzvibe（Cloudflare Tunnel）。`);
  };
  c.setAnnounce(announce);
  await announce();
  saveDaemonInfo();
  c.stopBonjour = advertiseBonjour({ name, port: c.port, connectorId: c.store.connector.id, log: console.log });
  await c.announceEndpoints('startup');

  const shutdown = async () => {
    if (stopping) return; stopping = true;
    console.log('\n[yzvibe] 正在退出…');
    tunnelChild?.kill(); await c.close(); clearDaemonInfo(); process.exit(0);
  };
  process.on('SIGINT', shutdown); process.on('SIGTERM', shutdown); process.on('SIGHUP', shutdown);
  return c;
}
