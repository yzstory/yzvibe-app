// APNs 远程推送：连接器直接连苹果推送服务，不经任何第三方。
// 这是「离开电脑也能收到审批」的关键——App 被系统挂起后 WebSocket 会断，只有远程推送能叫醒它。
//
// 配置 ~/.yzvibe/apns.json（或把 AuthKey_XXXXXXXXXX.p8 直接放进 ~/.yzvibe/，keyId 会从文件名推断）：
//   { "keyFile": "~/.yzvibe/AuthKey_ABCD123456.p8", "keyId": "ABCD123456",
//     "teamId": "TRVTR5HQP8", "bundleId": "icu.yzvibe.YzVibe", "environment": "sandbox" }
// environment: sandbox = Xcode 直接装到手机的调试版；production = TestFlight / App Store 版。
// 没配置就整体降级为「不推送」，其余功能不受影响。
import crypto from 'node:crypto';
import fs from 'node:fs';
import http2 from 'node:http2';
import os from 'node:os';
import path from 'node:path';
import { HOME } from './store.js';

const HOSTS = { production: 'https://api.push.apple.com', sandbox: 'https://api.sandbox.push.apple.com' };
const TOKEN_TTL = 50 * 60_000;          // 苹果要求 ≤ 60 分钟，提前 10 分钟换
const CONFIG_FILE = () => path.join(HOME, 'apns.json');

const expand = (p) => (p?.startsWith('~') ? path.join(os.homedir(), p.slice(1)) : p);

/** 读配置：apns.json 优先，其次环境变量，最后在 ~/.yzvibe/ 里找 AuthKey_*.p8 自动推断 keyId。 */
export function loadPushConfig(home = HOME) {
  let cfg = {};
  try { cfg = JSON.parse(fs.readFileSync(path.join(home, 'apns.json'), 'utf8')); } catch {}
  cfg = {
    keyFile: cfg.keyFile ?? process.env.YZVIBE_APNS_KEY ?? null,
    keyId: cfg.keyId ?? process.env.YZVIBE_APNS_KEY_ID ?? null,
    teamId: cfg.teamId ?? process.env.YZVIBE_APNS_TEAM_ID ?? null,
    bundleId: cfg.bundleId ?? process.env.YZVIBE_APNS_BUNDLE_ID ?? 'icu.yzvibe.YzVibe',
    environment: cfg.environment ?? process.env.YZVIBE_APNS_ENV ?? null,
  };
  if (!cfg.keyFile) {
    try {
      const f = fs.readdirSync(home).find((n) => /^AuthKey_[A-Z0-9]{10}\.p8$/i.test(n));
      if (f) { cfg.keyFile = path.join(home, f); cfg.keyId = cfg.keyId ?? f.slice(8, 18); }
    } catch {}
  } else if (!cfg.keyId) {
    const m = path.basename(cfg.keyFile).match(/^AuthKey_([A-Z0-9]{10})\.p8$/i);
    if (m) cfg.keyId = m[1];
  }
  const ready = Boolean(cfg.keyFile && cfg.keyId && cfg.teamId && cfg.bundleId && fs.existsSync(expand(cfg.keyFile)));
  let missing = null;
  if (!ready) {
    const gaps = [];
    if (!cfg.keyFile) gaps.push('推送密钥 .p8');
    else if (!fs.existsSync(expand(cfg.keyFile))) gaps.push(`密钥文件不存在：${cfg.keyFile}`);
    if (!cfg.keyId) gaps.push('keyId');
    if (!cfg.teamId) gaps.push('teamId');
    missing = gaps.join('、');
  }
  return { ...cfg, ready, missing, configFile: path.join(home, 'apns.json') };
}

/** 苹果要求的 ES256 JWT（缓存到快过期为止）。 */
export class ApnsAuth {
  constructor(cfg) { this.cfg = cfg; this.token = null; this.issuedAt = 0; }
  jwt() {
    if (this.token && Date.now() - this.issuedAt < TOKEN_TTL) return this.token;
    const key = crypto.createPrivateKey(fs.readFileSync(expand(this.cfg.keyFile), 'utf8'));
    const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
    const head = b64({ alg: 'ES256', kid: this.cfg.keyId });
    const body = b64({ iss: this.cfg.teamId, iat: Math.floor(Date.now() / 1000) });
    const sig = crypto.sign('SHA256', Buffer.from(`${head}.${body}`), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url');
    this.token = `${head}.${body}.${sig}`;
    this.issuedAt = Date.now();
    return this.token;
  }
}

/** APNs 的 aps 载荷（纯函数，便于测试）。 */
export function buildPayload(note = {}) {
  if (note.silent) return { aps: { 'content-available': 1, ...(note.badge != null && { badge: note.badge }) }, yz: note.data ?? {} };
  return {
    aps: {
      alert: { title: note.title, body: note.body },
      sound: note.sound ?? 'default',
      ...(note.badge != null && { badge: note.badge }),
      'interruption-level': note.level ?? 'time-sensitive',
      'thread-id': note.threadId ?? 'yzvibe',
      ...(note.category && { category: note.category }),
    },
    yz: note.data ?? {},
  };
}

/** APNs 请求头（纯函数，便于测试）。 */
export function buildHeaders(note = {}, { jwt, bundleId }) {
  return {
    authorization: `bearer ${jwt}`,
    'apns-topic': bundleId,
    'apns-push-type': note.silent ? 'background' : 'alert',
    'apns-priority': note.silent ? '5' : '10',
    'apns-expiration': String(Math.floor(Date.now() / 1000) + (note.ttlSeconds ?? 600)),
    ...(note.collapseId && { 'apns-collapse-id': String(note.collapseId).slice(0, 64) }),
    'content-type': 'application/json',
  };
}

/** 一条推送的结果：{ ok, status, reason }。reason 见苹果文档（BadDeviceToken / Unregistered …）。 */
async function post(host, deviceToken, headers, payload, { timeoutMs = 10_000, sessions } = {}) {
  const client = sessions ? sessions.get(host) : null;
  const conn = client && !client.closed && !client.destroyed ? client : http2.connect(host);
  if (sessions && conn !== client) {
    sessions.set(host, conn);
    conn.on('error', () => sessions.delete(host));
    conn.on('close', () => { if (sessions.get(host) === conn) sessions.delete(host); });
    conn.setTimeout(5 * 60_000, () => conn.close());
  }
  return new Promise((resolve) => {
    let done = false;
    const finish = (r) => { if (!done) { done = true; resolve(r); } };
    let req;
    try { req = conn.request({ ':method': 'POST', ':path': `/3/device/${deviceToken}`, ...headers }); }
    catch (e) { return finish({ ok: false, status: 0, reason: e.message }); }
    const timer = setTimeout(() => { try { req.close(); } catch {} finish({ ok: false, status: 0, reason: 'timeout' }); }, timeoutMs);
    let status = 0, body = '';
    req.on('response', (h) => { status = Number(h[':status'] ?? 0); });
    req.on('data', (d) => { body += d; });
    req.on('error', (e) => { clearTimeout(timer); finish({ ok: false, status: 0, reason: e.message }); });
    req.on('end', () => {
      clearTimeout(timer);
      let reason = null;
      if (body) { try { reason = JSON.parse(body).reason ?? null; } catch { reason = body.slice(0, 120); } }
      finish({ ok: status === 200, status, reason });
    });
    req.end(JSON.stringify(payload));
  });
}

/**
 * 推送器。`send()` 对所有已注册推送的设备发一条；返回每台设备的结果。
 * 设备 token 无效（Unregistered / BadDeviceToken）时通过 onInvalid 回调让 store 清掉。
 */
export class Pusher {
  constructor({ home = HOME, onInvalid = () => {}, log = console.log, fetchConfig = loadPushConfig, postImpl = post } = {}) {
    this.home = home; this.onInvalid = onInvalid; this.log = log; this.fetchConfig = fetchConfig; this.postImpl = postImpl;
    this.sessions = new Map();
    this.reload();
  }

  reload() {
    this.config = this.fetchConfig(this.home);
    this.auth = this.config.ready ? new ApnsAuth(this.config) : null;
    return this.config;
  }

  get ready() { return Boolean(this.config.ready); }

  /** 状态摘要（yzvibe status / GET /internal/status 用）。 */
  status(devices = []) {
    const registered = devices.filter((d) => d.push?.token).length;
    return {
      ready: this.ready,
      environment: this.config.environment ?? 'auto',
      bundleId: this.config.bundleId,
      registeredDevices: registered,
      configFile: this.config.configFile,
      ...(this.ready ? {} : { missing: this.config.missing }),
    };
  }

  /**
   * @param devices 已配对设备（含 push:{token, environment}）
   * @param note { title, body, category, threadId, collapseId, badge, data, silent }
   */
  async send(devices, note) {
    if (!this.ready) return [];
    const targets = devices.filter((d) => d.push?.token);
    if (!targets.length) return [];
    const jwt = this.auth.jwt();
    const payload = buildPayload(note);
    const headers = buildHeaders(note, { jwt, bundleId: this.config.bundleId });

    return Promise.all(targets.map(async (d) => {
      const first = d.push.environment ?? this.config.environment ?? 'sandbox';
      const order = first === 'production' ? ['production', 'sandbox'] : ['sandbox', 'production'];
      let last = null;
      for (const env of order) {
        const r = await this.postImpl(HOSTS[env], d.push.token, headers, payload, { sessions: this.sessions });
        last = { deviceId: d.id, environment: env, ...r };
        if (r.ok) { if (d.push.environment !== env) this.onInvalid(d.id, { keep: true, environment: env }); return last; }
        // 环境不匹配才换一个再试；其它错误直接返回
        if (r.reason !== 'BadDeviceToken' && r.status !== 400) break;
      }
      if (last && ['Unregistered', 'BadDeviceToken', 'DeviceTokenNotForTopic'].includes(last.reason)) {
        this.log(`[yzvibe] 推送目标失效（${last.reason}），已清除该手机的推送 token`);
        this.onInvalid(last.deviceId, { keep: false });
      } else if (last && !last.ok) {
        this.log(`[yzvibe] 推送失败：HTTP ${last.status} ${last.reason ?? ''}`);
      }
      return last;
    }));
  }

  /**
   * 更新锁屏 / 灵动岛上的实时活动。手机在 App 里开活动时把 token 交过来，
   * 之后即使 App 被挂起，这里也能把「在跑什么、要不要批」推上去。
   * @param targets [{ deviceId, token, environment }]
   * @param state   与 iOS 端 SessionActivityAttributes.ContentState 字段一致
   */
  async sendLiveActivity(targets, { state, event = 'update', staleSeconds = 600, dismissSeconds = 0 }) {
    if (!this.ready || !targets.length) return [];
    const jwt = this.auth.jwt();
    const now = Math.floor(Date.now() / 1000);
    const payload = {
      aps: {
        timestamp: now,
        event,
        'content-state': state,
        ...(event === 'update' ? { 'stale-date': now + staleSeconds } : {}),
        ...(event === 'end' && dismissSeconds ? { 'dismissal-date': now + dismissSeconds } : {}),
      },
    };
    const headers = {
      authorization: `bearer ${jwt}`,
      'apns-topic': `${this.config.bundleId}.push-type.liveactivity`,
      'apns-push-type': 'liveactivity',
      'apns-priority': '10',
      'apns-expiration': String(now + staleSeconds),
      'content-type': 'application/json',
    };
    return Promise.all(targets.map(async (t) => {
      const env = t.environment ?? this.config.environment ?? 'sandbox';
      const r = await this.postImpl(HOSTS[env], t.token, headers, payload, { sessions: this.sessions });
      if (!r.ok && ['Unregistered', 'BadDeviceToken', 'ExpiredToken'].includes(r.reason)) this.onInvalid(t.deviceId, { keep: true, activityToken: t.token, drop: true });
      return { ...t, ...r };
    }));
  }

  close() { for (const c of this.sessions.values()) { try { c.close(); } catch {} } this.sessions.clear(); }
}
