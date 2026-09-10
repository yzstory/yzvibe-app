// 服务端集成：一次性同步、规则接口、推送注册、设备撤销、定期清理。
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { WebSocket } from 'ws';
import { createConnector } from '../src/server.js';
import { Store } from '../src/store.js';
import { runCleanup, pruneUploads, pruneSessions, pruneOrphanMessages } from '../src/cleanup.js';

async function boot(opts = {}) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-maint-'));
  const c = await createConnector({ port: 0, name: 'T', defaultAgent: 'mock', home, log: () => {}, importTerminal: false, ...opts });
  const port = await c.listen();
  const base = `http://127.0.0.1:${port}`;
  const pair = await (await fetch(`${base}/pair`, { method: 'POST', body: JSON.stringify({ token: c.pairing.token, phoneName: 'iPhone' }) })).json();
  const H = { authorization: `Bearer ${pair.deviceToken}`, 'content-type': 'application/json' };
  return { c, base, H, home, port, deviceToken: pair.deviceToken };
}

test('GET /sync：一次拿到会话 / 待审批 / 能力表 / 规则 / 推送状态', async () => {
  const { c, base, H } = await boot();
  const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-cwd-'));
  await (await fetch(`${base}/sessions`, { method: 'POST', headers: H, body: JSON.stringify({ agent: 'mock', cwd }) })).json();
  const sync = await (await fetch(`${base}/sync`, { headers: H })).json();
  assert.equal(sync.sessions.length, 1);
  assert.deepEqual(sync.approvals, []);
  assert.ok(sync.agents.claude.modes.plan);
  assert.equal(sync.push.ready, false);              // 本机没配 APNs 密钥
  assert.match(sync.push.missing, /推送密钥/);
  assert.ok(Date.parse(sync.serverTime) > 0);
  assert.equal((await fetch(`${base}/sync`)).status, 401);
  await c.close();
});

test('规则接口：增 / 查 / 删；删掉后重新开始询问', async () => {
  const { c, base, H } = await boot();
  const created = await (await fetch(`${base}/rules`, { method: 'POST', headers: H, body: JSON.stringify({ sessionId: 's1', tool: 'Bash', match: 'prefix', value: 'git status', scope: 'session' }) })).json();
  assert.ok(created.id);
  assert.match(created.description, /本会话内放行以 git status 开头/);

  const list = await (await fetch(`${base}/rules?sessionId=s1`, { headers: H })).json();
  assert.equal(list.length, 1);
  assert.equal((await (await fetch(`${base}/rules?sessionId=other`, { headers: H })).json()).length, 0);

  assert.equal((await fetch(`${base}/rules/${created.id}`, { method: 'DELETE', headers: H })).status, 200);
  assert.equal((await fetch(`${base}/rules/${created.id}`, { method: 'DELETE', headers: H })).status, 404);
  assert.equal((await (await fetch(`${base}/rules`, { headers: H })).json()).length, 0);

  // 非法规则被拒绝
  assert.equal((await fetch(`${base}/rules`, { method: 'POST', headers: H, body: JSON.stringify({ match: 'regex', value: '.*' }) })).status, 400);
  await c.close();
});

test('推送注册：token 校验、写入设备、可注销', async () => {
  const { c, base, H } = await boot();
  assert.equal((await fetch(`${base}/devices/push`, { method: 'POST', headers: H, body: JSON.stringify({ token: 'nope' }) })).status, 400);

  const token = 'a1b2c3d4'.repeat(8);
  const ok = await (await fetch(`${base}/devices/push`, { method: 'POST', headers: H, body: JSON.stringify({ token, environment: 'production' }) })).json();
  assert.equal(ok.ok, true);
  assert.equal(c.store.devices[0].push.token, token);
  assert.equal(c.store.devices[0].push.environment, 'production');
  assert.equal(c.store.listDevices()[0].push.environment, 'production');
  assert.equal(c.store.listDevices()[0].token, undefined, '对外不暴露设备 Token');

  await fetch(`${base}/devices/push`, { method: 'DELETE', headers: H });
  assert.equal(c.store.devices[0].push, null);
  await c.close();
});

test('设备管理：本机 CLI 能列出并撤销手机，撤销后连接立刻断开且 Token 失效', async () => {
  const { c, base, H, port, deviceToken } = await boot();
  const S = { 'x-yzvibe-secret': c.internalSecret };

  assert.equal((await fetch(`${base}/internal/devices`)).status, 403);
  const devices = await (await fetch(`${base}/internal/devices`, { headers: S })).json();
  assert.equal(devices.length, 1);
  assert.equal(devices[0].name, 'iPhone');

  const ws = new WebSocket(`ws://127.0.0.1:${port}/ws?token=${deviceToken}`);
  await new Promise((r) => ws.on('open', r));
  const closed = new Promise((r) => ws.on('close', r));

  const revoked = await (await fetch(`${base}/internal/devices/${devices[0].id.slice(0, 8)}`, { method: 'DELETE', headers: S })).json();
  assert.equal(revoked.ok, true);
  await closed;                                             // 撤销后连接被踢掉
  assert.equal((await fetch(`${base}/sessions`, { headers: H })).status, 401);
  assert.equal((await fetch(`${base}/internal/devices/nope`, { method: 'DELETE', headers: S })).status, 404);
  await c.close();
});

test('推送自检接口：没配置密钥时如实返回未就绪', async () => {
  const { c, base } = await boot();
  const r = await (await fetch(`${base}/internal/push-test`, { method: 'POST', headers: { 'x-yzvibe-secret': c.internalSecret } })).json();
  assert.equal(r.ok, false);
  assert.equal(r.status.ready, false);
  await c.close();
});

test('定期清理：旧图片、过期会话、孤儿消息文件', () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-clean-'));
  const store = new Store(home);
  const old = new Date(Date.now() - 60 * 86400_000).toISOString();

  const fresh = store.createSession({ agent: 'claude', cwd: os.tmpdir(), title: '在用' });
  store.addMessage(fresh.id, { role: 'user', text: 'hi' });
  const stale = store.createSession({ agent: 'claude', cwd: os.tmpdir(), title: '很久以前' });
  store.addMessage(stale.id, { role: 'user', text: 'old' });
  stale.status = 'closed'; stale.updatedAt = old;

  // 一新一旧两张图
  const keepId = store.addUpload('new.png', 'image/png', Buffer.from([1]));
  const dropId = store.addUpload('old.png', 'image/png', Buffer.from([1]));
  const dropFile = store.upload(dropId).path;
  fs.utimesSync(dropFile, new Date(Date.now() - 30 * 86400_000), new Date(Date.now() - 30 * 86400_000));
  // 一个没有对应会话的消息文件
  fs.writeFileSync(path.join(home, 'messages', 'ghost.json'), '[]');

  const r = runCleanup(store, { log: () => {} });
  assert.equal(r.uploads.removed, 1);
  assert.equal(r.sessions, 1);
  assert.equal(r.orphans, 1);
  assert.ok(fs.existsSync(store.upload(keepId).path));
  assert.equal(fs.existsSync(dropFile), false);
  assert.equal(fs.existsSync(path.join(home, 'messages', `${stale.id}.json`)), false);
  assert.ok(fs.existsSync(path.join(home, 'messages', `${fresh.id}.json`)));
  assert.deepEqual(store.sessions.map((s) => s.id), [fresh.id]);

  // 重跑一次不该再删任何东西
  assert.deepEqual(runCleanup(store, { log: () => {} }), { uploads: { removed: 0, bytes: 0 }, sessions: 0, orphans: 0 });
  // 目录不存在也不该抛
  assert.deepEqual(pruneUploads(path.join(home, 'nope')), { removed: 0, bytes: 0 });
  assert.deepEqual(pruneSessions([], home), []);
  assert.equal(pruneOrphanMessages(store.sessions, path.join(home, 'nope')), 0);
});
