// 远程推送（APNs）与审批规则。推送不真连苹果服务器：post 用注入的实现，验证 JWT、载荷、失效清理与环境回退。
import { test } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Pusher, ApnsAuth, loadPushConfig, buildPayload, buildHeaders } from '../src/push.js';
import { Rules, commandPrefix, suggestionsFor } from '../src/rules.js';
import { Store, describeRule } from '../src/store.js';

/** 造一个临时的 ~/.yzvibe：一把 EC 私钥 + apns.json。 */
function pushHome({ withConfig = true, keyName = 'AuthKey_ABCD123456.p8' } = {}) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-push-'));
  const { privateKey, publicKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
  fs.writeFileSync(path.join(home, keyName), privateKey.export({ type: 'pkcs8', format: 'pem' }));
  if (withConfig) fs.writeFileSync(path.join(home, 'apns.json'), JSON.stringify({ teamId: 'TEAM123456', bundleId: 'icu.yzvibe.YzVibe', environment: 'sandbox' }));
  return { home, publicKey };
}

test('推送配置：从 .p8 文件名推断 keyId；缺 teamId 时降级并说明缺什么', () => {
  const { home } = pushHome();
  const cfg = loadPushConfig(home);
  assert.equal(cfg.ready, true);
  assert.equal(cfg.keyId, 'ABCD123456');
  assert.equal(cfg.teamId, 'TEAM123456');

  const bare = fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-nopush-'));
  const none = loadPushConfig(bare);
  assert.equal(none.ready, false);
  assert.match(none.missing, /推送密钥/);
});

test('APNs JWT：ES256 结构正确且签名可验证', () => {
  const { home, publicKey } = pushHome();
  const cfg = loadPushConfig(home);
  const jwt = new ApnsAuth(cfg).jwt();
  const [h, b, sig] = jwt.split('.');
  assert.deepEqual(JSON.parse(Buffer.from(h, 'base64url')), { alg: 'ES256', kid: 'ABCD123456' });
  assert.equal(JSON.parse(Buffer.from(b, 'base64url')).iss, 'TEAM123456');
  const ok = crypto.verify('SHA256', Buffer.from(`${h}.${b}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(sig, 'base64url'));
  assert.equal(ok, true);
});

test('推送载荷：审批用 time-sensitive，静默推送只带 content-available', () => {
  const alert = buildPayload({ title: '需要批准', body: 'rm -rf dist', badge: 2, threadId: 's1', category: 'APPROVAL', data: { kind: 'approval' } });
  assert.equal(alert.aps['interruption-level'], 'time-sensitive');
  assert.equal(alert.aps.alert.title, '需要批准');
  assert.equal(alert.aps.badge, 2);
  assert.equal(alert.yz.kind, 'approval');
  const silent = buildPayload({ silent: true, badge: 0, data: { kind: 'x' } });
  assert.equal(silent.aps['content-available'], 1);
  assert.equal(silent.aps.alert, undefined);
  const h = buildHeaders({ collapseId: 'approval-1' }, { jwt: 'J', bundleId: 'icu.yzvibe.YzVibe' });
  assert.equal(h['apns-topic'], 'icu.yzvibe.YzVibe');
  assert.equal(h['apns-priority'], '10');
  assert.equal(h['apns-collapse-id'], 'approval-1');
});

test('推送发送：没配置就静默跳过；token 失效会被清掉；环境不对会换一个再试', async () => {
  const bare = fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-nopush-'));
  assert.deepEqual(await new Pusher({ home: bare, log: () => {} }).send([{ id: 'd', push: { token: 'x' } }], { title: 'a' }), []);

  const { home } = pushHome();
  const calls = [];
  const invalid = [];
  const pusher = new Pusher({
    home, log: () => {}, onInvalid: (id, info) => invalid.push({ id, ...info }),
    postImpl: async (host, token) => {
      calls.push({ host, token });
      if (token === 'good'.repeat(10)) return { ok: true, status: 200, reason: null };
      if (token === 'gone'.repeat(10)) return { ok: false, status: 410, reason: 'Unregistered' };
      return host.includes('sandbox') ? { ok: false, status: 400, reason: 'BadDeviceToken' } : { ok: true, status: 200, reason: null };
    },
  });
  assert.equal(pusher.ready, true);
  const devices = [
    { id: 'd1', push: { token: 'good'.repeat(10), environment: 'sandbox' } },
    { id: 'd2', push: { token: 'gone'.repeat(10), environment: 'sandbox' } },
    { id: 'd3', push: { token: 'prod'.repeat(10), environment: 'sandbox' } },   // 其实是生产环境的 token
    { id: 'd4', push: null },                                                    // 没注册推送
  ];
  const results = await pusher.send(devices, { title: 't', body: 'b' });
  assert.equal(results.length, 3);
  assert.equal(results[0].ok, true);
  assert.equal(results[1].ok, false);
  assert.equal(results[2].ok, true);
  assert.equal(results[2].environment, 'production');                            // 自动换到生产环境成功
  assert.deepEqual(invalid.filter((x) => !x.keep).map((x) => x.id), ['d2']);      // 失效的被清掉
  assert.ok(invalid.some((x) => x.id === 'd3' && x.keep && x.environment === 'production'));
  assert.equal(pusher.status(devices).registeredDevices, 3);
});

test('规则：按工具 / 按命令前缀匹配，过期自动失效，可持久化与删除', () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-rules-'));
  const r = new Rules(home);
  const req = { sessionId: 's1', agent: 'claude', toolName: 'Bash', summary: 'npm test -- --watch' };

  assert.equal(r.match(req), null);
  r.add({ sessionId: 's1', tool: 'Bash', match: 'prefix', value: 'npm test', scope: 'session' });
  assert.ok(r.match(req));
  assert.equal(r.match({ ...req, summary: 'rm -rf dist' }), null);        // 前缀不同不放行
  assert.equal(r.match({ ...req, sessionId: 's2' }), null);               // 换个会话不放行

  // 全局 + 限时
  r.add({ tool: 'Read', match: 'tool', scope: 'global', ttlMinutes: 60 });
  assert.ok(r.match({ sessionId: 'any', toolName: 'Read', summary: '/a/b' }));
  const expired = r.add({ tool: 'Write', match: 'tool', scope: 'global', ttlMinutes: 1 });
  expired.expiresAt = new Date(Date.now() - 1000).toISOString();
  assert.equal(r.match({ sessionId: 'any', toolName: 'Write', summary: 'x' }), null);
  assert.equal(r.all().some((x) => x.id === expired.id), false);

  // 落盘后新实例还在
  const again = new Rules(home);
  assert.equal(again.all().length, 2);
  assert.ok(again.match(req));
  assert.equal(again.match(req).hits >= 1, true);

  // 删除 / 按会话清空
  assert.equal(again.remove(again.all()[0].id), true);
  again.removeForSession('s1');
  assert.equal(again.all().every((x) => x.sessionId !== 's1'), true);
});

test('规则建议：命令前缀取到子命令，写文件给整会话放行选项', () => {
  assert.equal(commandPrefix('git status --short'), 'git status');
  assert.equal(commandPrefix('npm run build'), 'npm run');
  assert.equal(commandPrefix('./scripts/x.sh -v'), './scripts/x.sh');
  assert.equal(commandPrefix('ls -la'), 'ls');
  assert.equal(commandPrefix(''), '');

  const s = suggestionsFor({ toolName: 'Bash', kind: 'shell', summary: 'npm test' });
  assert.equal(s[0].match, 'prefix');
  assert.equal(s[0].value, 'npm test');
  assert.ok(s.some((x) => x.match === 'tool' && x.ttlMinutes === 60));
  assert.ok(suggestionsFor({ toolName: 'Edit', kind: 'write', summary: '/a.ts' }).some((x) => x.ttlMinutes === null));
});

test('规则命中：审批直接放行并在聊天里留痕', async () => {
  const store = new Store(fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-ruleapp-')));
  store.rules = new Rules(store.home);
  const s = store.createSession({ agent: 'claude', cwd: os.tmpdir(), title: 'x' });
  store.rules.add({ sessionId: s.id, tool: 'Bash', match: 'prefix', value: 'npm test', scope: 'session' });
  const decision = await store.requestApproval({ sessionId: s.id, toolName: 'Bash', kind: 'shell', summary: 'npm test -- -u', detail: '', risk: 'medium', agent: 'claude' });
  assert.equal(decision, 'allow');
  assert.equal(store.listApprovals('pending').length, 0);
  assert.match(store.messagesOf(s.id).at(-1).text, /已按规则自动允许/);
  assert.match(describeRule(store.rules.all()[0]), /本会话内放行以 npm test 开头/);
});
