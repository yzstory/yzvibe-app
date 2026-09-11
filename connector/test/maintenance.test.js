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

test('消息队列：忙时排队、本轮结束自动接上、可取消、可插队打断', async () => {
  const { c, base, H, port } = await boot();
  const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-q-'));
  const ws = new WebSocket(`ws://127.0.0.1:${port}/ws?token=${(await (await fetch(`${base}/sync`, { headers: H })).json()) && H.authorization.replace('Bearer ', '')}`);
  const events = [];
  await new Promise((r) => ws.on('open', r));
  ws.on('message', (d) => events.push(JSON.parse(d)));
  const waitFor = (pred, ms = 8000) => new Promise((res, rej) => { const t0 = Date.now(); const tick = () => { const e = events.find(pred); if (e) return res(e); if (Date.now() - t0 > ms) return rej(new Error('timeout')); setTimeout(tick, 20); }; tick(); });

  const s = await (await fetch(`${base}/sessions`, { method: 'POST', headers: H, body: JSON.stringify({ agent: 'mock', cwd, firstMessage: '开始干活' }) })).json();
  await waitFor((e) => e.type === 'session.status' && e.status === 'running');

  // 正忙的时候再发两条：默认排队，不打断
  const r1 = await (await fetch(`${base}/sessions/${s.id}/messages`, { method: 'POST', headers: H, body: JSON.stringify({ text: '排队一号' }) })).json();
  const r2 = await (await fetch(`${base}/sessions/${s.id}/messages`, { method: 'POST', headers: H, body: JSON.stringify({ text: '排队二号' }) })).json();
  assert.equal(r1.queued, true);
  assert.equal(r2.queued, true);
  assert.equal(c.store.session(s.id).queue.length, 2);
  const queued = await waitFor((e) => e.type === 'session.updated' && e.session.queue?.length === 2);
  assert.deepEqual(queued.session.queue.map((x) => x.text), ['排队一号', '排队二号']);

  // 取消第二条
  assert.equal((await fetch(`${base}/sessions/${s.id}/queue/${r2.item.id}`, { method: 'DELETE', headers: H })).status, 200);
  assert.equal(c.store.session(s.id).queue.length, 1);
  assert.equal((await fetch(`${base}/sessions/${s.id}/queue/nope`, { method: 'DELETE', headers: H })).status, 404);

  // 本轮结束后排队的自动发出去
  await waitFor((e) => e.type === 'session.updated' && (e.session.queue?.length ?? 0) === 0 && e.session.id === s.id, 15000);
  const msgs = await (await fetch(`${base}/sessions/${s.id}/messages`, { headers: H })).json();
  assert.ok(msgs.some((x) => x.role === 'user' && x.text === '排队一号'), '排队的消息应该被真的发出去');
  assert.ok(!msgs.some((x) => x.text === '排队二号'), '取消掉的不该被发出去');

  ws.close();
  await c.close();
});

test('会话改动视图与命令清单', async () => {
  const { c, base, H } = await boot();
  const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-git-'));
  const s = await (await fetch(`${base}/sessions`, { method: 'POST', headers: H, body: JSON.stringify({ agent: 'mock', cwd }) })).json();

  // 不是 git 仓库时要给一句人话，而不是空白
  const nodiff = await (await fetch(`${base}/sessions/${s.id}/diff`, { headers: H })).json();
  assert.equal(nodiff.repo, false);
  assert.match(nodiff.reason, /git/);

  // 命令清单：app 命令 + skill
  const cmds = await (await fetch(`${base}/sessions/${s.id}/commands`, { headers: H })).json();
  assert.ok(cmds.app.some((x) => x.name === 'new' && x.action === 'new-session'));
  assert.ok(cmds.app.some((x) => x.name === 'diff'));
  assert.ok(Array.isArray(cmds.skills));
  assert.equal((await fetch(`${base}/sessions/nope/commands`, { headers: H })).status, 404);
  await c.close();
});

test('地址稳定性：/health 报出所有可达地址，配对配置里也带着', async () => {
  const { c, base, H } = await boot();
  c.access = { host: 'https://abc.trycloudflare.com', mode: 'tunnel' };

  const health = await (await fetch(`${base}/health`)).json();
  assert.ok(Array.isArray(health.endpoints) && health.endpoints.length >= 2, '至少要有隧道地址和一个局域网地址');
  assert.equal(health.endpoints[0], 'https://abc.trycloudflare.com');
  assert.ok(health.endpoints.some((e) => e.startsWith('http://') && e.endsWith(`:${c.port}`)));

  const st = await (await fetch(`${base}/internal/status`, { headers: { 'x-yzvibe-secret': c.internalSecret } })).json();
  assert.deepEqual(st.endpoints, health.endpoints);
  assert.deepEqual(st.pairing.config.endpoints, health.endpoints, '配对配置要带上备用地址，手机才能在隧道换地址后自己接上');
  await c.close();
});

test('实时活动 token：注册、按会话取回、失效清理', async () => {
  const { c, base, H } = await boot();
  const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-la-'));
  const s = await (await fetch(`${base}/sessions`, { method: 'POST', headers: H, body: JSON.stringify({ agent: 'mock', cwd }) })).json();
  const token = 'ab'.repeat(40);

  assert.equal((await fetch(`${base}/devices/live-activity`, { method: 'POST', headers: H, body: JSON.stringify({ sessionId: s.id, token: 'short' }) })).status, 400);
  assert.equal((await fetch(`${base}/devices/live-activity`, { method: 'POST', headers: H, body: JSON.stringify({ sessionId: s.id, token, environment: 'production' }) })).status, 200);

  const list = c.store.liveActivitiesFor(s.id);
  assert.equal(list.length, 1);
  assert.equal(list[0].environment, 'production');
  assert.equal(c.store.liveActivitiesFor('other').length, 0);

  // 同一会话再注册一次只会留最新的那个
  await fetch(`${base}/devices/live-activity`, { method: 'POST', headers: H, body: JSON.stringify({ sessionId: s.id, token: 'cd'.repeat(40) }) });
  assert.equal(c.store.liveActivitiesFor(s.id).length, 1);

  c.store.dropLiveActivity('cd'.repeat(40));
  assert.equal(c.store.liveActivitiesFor(s.id).length, 0);
  await c.close();
});

test('删除会话：本地记录清干净，终端会话也不会被重新扫回来', async () => {
  const claudeHome = fs.mkdtempSync(path.join(os.tmpdir(), 'yz-del-claude-'));
  const codexHome = fs.mkdtempSync(path.join(os.tmpdir(), 'yz-del-codex-'));
  const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-del-cwd-'));
  const proj = path.join(claudeHome, 'projects', '-tmp-del'); fs.mkdirSync(proj, { recursive: true });
  const sid = '99999999-8888-7777-6666-555555555555';
  fs.writeFileSync(path.join(proj, `${sid}.jsonl`), [
    JSON.stringify({ type: 'attachment', cwd, gitBranch: 'main', entrypoint: 'cli', sessionId: sid, timestamp: '2026-09-11T10:00:00.000Z', uuid: 'y0' }),
    JSON.stringify({ type: 'user', message: { role: 'user', content: [{ type: 'text', text: '终端里聊过的' }] }, uuid: 'y1', timestamp: '2026-09-11T10:00:01.000Z', cwd }),
  ].join('\n') + '\n'.padEnd(200, ' '));

  const { c, base, H, home, port } = await boot({ claudeHome, codexHome, importTerminal: true });
  const ws = new WebSocket(`ws://127.0.0.1:${port}/ws?token=${H.authorization.replace('Bearer ', '')}`);
  const events = [];
  await new Promise((r) => ws.on('open', r));
  ws.on('message', (d) => events.push(JSON.parse(d)));

  const s = await (await fetch(`${base}/sessions`, { method: 'POST', headers: H, body: JSON.stringify({ agent: 'mock', cwd }) })).json();
  const ids = async () => (await (await fetch(`${base}/sessions`, { headers: H })).json()).map((x) => x.id);
  assert.ok((await ids()).includes(s.id));
  assert.ok((await ids()).includes(`claude:${sid}`));

  // 手机端删掉自己建的会话：列表、消息文件、规则都清掉，并广播出去
  assert.equal((await fetch(`${base}/sessions/${s.id}`, { method: 'DELETE', headers: H })).status, 200);
  assert.ok(!(await ids()).includes(s.id));
  assert.equal(fs.existsSync(path.join(home, 'messages', `${s.id}.json`)), false);
  await new Promise((r) => setTimeout(r, 50));
  assert.ok(events.some((e) => e.type === 'session.removed' && e.sessionId === s.id));

  // 终端扫出来的会话：删掉后再扫也不该回来
  assert.equal((await fetch(`${base}/sessions/claude:${sid}`, { method: 'DELETE', headers: H })).status, 200);
  assert.ok(!(await ids()).includes(`claude:${sid}`));
  assert.equal((await fetch(`${base}/sessions/claude:${sid}`, { headers: H })).status, 404);
  const sync = await (await fetch(`${base}/sync`, { headers: H })).json();
  assert.equal(sync.hiddenSessions, 2);
  assert.deepEqual((await (await fetch(`${base}/sessions/hidden`, { headers: H })).json()).ids.sort(), [s.id, `claude:${sid}`].sort());

  // 恢复：终端会话重新出现，自己建的那条已经真删了不会回来
  assert.equal((await (await fetch(`${base}/sessions/hidden`, { method: 'DELETE', headers: H })).json()).restored, 2);
  const after = await ids();
  assert.ok(after.includes(`claude:${sid}`));
  assert.ok(!after.includes(s.id));

  ws.close();
  await c.close();
});
