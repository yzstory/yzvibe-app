import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { WebSocket } from 'ws';
import { createConnector } from '../src/server.js';
import { classifyPermission } from '../src/agents/claude.js';

const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-test-'));
const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-cwd-'));
fs.writeFileSync(path.join(cwd, 'hello.md'), '# hi');
fs.mkdirSync(path.join(cwd, 'src'));

test('配对 → 会话 → WS 流式回复 → 审批 → 文件', async () => {
  const c = await createConnector({ port: 0, name: 'TestMac', defaultAgent: 'mock', home: tmpHome, log: () => {} });
  const port = await c.listen();
  const base = `http://127.0.0.1:${port}`;

  // health 公开
  const health = await (await fetch(`${base}/health`)).json();
  assert.equal(health.name, 'TestMac');
  assert.ok(health.connectorId);

  // 未配对 401
  assert.equal((await fetch(`${base}/sessions`)).status, 401);

  // 配对：错 token 拒绝，对 token 通过且一次性
  assert.equal((await fetch(`${base}/pair`, { method: 'POST', body: JSON.stringify({ token: 'nope' }) })).status, 401);
  const token = c.pairing.token;
  const pair = await (await fetch(`${base}/pair`, { method: 'POST', body: JSON.stringify({ token, phoneName: 'iPhone' }) })).json();
  assert.ok(pair.deviceToken); assert.equal(pair.connectorId, health.connectorId);
  assert.equal((await fetch(`${base}/pair`, { method: 'POST', body: JSON.stringify({ token }) })).status, 401);
  const H = { authorization: `Bearer ${pair.deviceToken}`, 'content-type': 'application/json' };

  // WS 连接并收集事件
  const ws = new WebSocket(`ws://127.0.0.1:${port}/ws?token=${pair.deviceToken}`);
  const events = [];
  await new Promise((r) => ws.on('open', r));
  ws.on('message', (d) => events.push(JSON.parse(d)));
  const waitFor = (pred, ms = 5000) => new Promise((res, rej) => { const t0 = Date.now(); const tick = () => { const e = events.find(pred); if (e) return res(e); if (Date.now() - t0 > ms) return rej(new Error('timeout waiting ' + pred)); setTimeout(tick, 30); }; tick(); });

  // 工作目录不存在 → 400
  assert.equal((await fetch(`${base}/sessions`, { method: 'POST', headers: H, body: JSON.stringify({ agent: 'mock', cwd: '/definitely/not/here' }) })).status, 400);

  // 新建会话（带首条消息，触发 mock 的审批）
  const s = await (await fetch(`${base}/sessions`, { method: 'POST', headers: H, body: JSON.stringify({ agent: 'mock', cwd, firstMessage: '请删除 dist 目录' }) })).json();
  assert.equal(s.cwd, cwd);
  await waitFor((e) => e.type === 'session.created');
  await waitFor((e) => e.type === 'message.delta' && e.sessionId === s.id);
  await waitFor((e) => e.type === 'tool.call' && e.state === 'done');
  const approval = await waitFor((e) => e.type === 'approval.requested');
  assert.equal(approval.risk, 'high');

  // 审批收件箱能查到，会话状态为 waiting_approval
  const pending = await (await fetch(`${base}/approvals?status=pending`, { headers: H })).json();
  assert.equal(pending.length, 1);
  assert.equal((await (await fetch(`${base}/sessions/${s.id}`, { headers: H })).json()).status, 'waiting_approval');

  // 通过 WS 批准 → resolved → agent 继续 → idle
  ws.send(JSON.stringify({ type: 'approval.respond', approvalId: approval.approvalId, decision: 'allow' }));
  await waitFor((e) => e.type === 'approval.resolved' && e.decision === 'allow');
  await waitFor((e) => e.type === 'session.status' && e.status === 'idle' && events.filter((x) => x.type === 'message.done').length >= 2);
  const msgs = await (await fetch(`${base}/sessions/${s.id}/messages`, { headers: H })).json();
  assert.ok(msgs.some((m) => m.role === 'user' && m.text === '请删除 dist 目录'));
  assert.ok(msgs.some((m) => m.role === 'system' && m.approvalId === approval.approvalId));
  assert.ok(msgs.some((m) => m.role === 'assistant' && m.text.includes('已删除')));

  // 同样的命令第二次自动放行（autoAllow），不再产生新审批
  ws.send(JSON.stringify({ type: 'message.send', sessionId: s.id, text: '再删除一次 dist' }));
  await waitFor((e) => e.type === 'message.done' && events.filter((x) => x.type === 'message.done').length >= 4, 8000);
  assert.equal(events.filter((e) => e.type === 'approval.requested').length, 1);

  // 文件：列表 / 预览 / 越界
  const files = await (await fetch(`${base}/files?sessionId=${s.id}&path=`, { headers: H })).json();
  assert.deepEqual(files.entries.map((e) => e.name), ['src', 'hello.md']);
  assert.equal(await (await fetch(`${base}/files/preview?sessionId=${s.id}&path=hello.md`, { headers: H })).text(), '# hi');
  assert.equal((await fetch(`${base}/files?sessionId=${s.id}&path=../../`, { headers: H })).status, 403);

  // 上传
  const up = await (await fetch(`${base}/uploads`, { method: 'POST', headers: { authorization: H.authorization, 'content-type': 'image/png', 'x-filename': 'a.png' }, body: Buffer.from([1, 2, 3]) })).json();
  assert.ok(up.id);
  assert.equal((await fetch(`${base}${up.url}`, { headers: H })).status, 200);

  ws.close();
  await c.close();
});

test('权限分类', () => {
  assert.equal(classifyPermission('Bash', { command: 'rm -rf dist' }).risk, 'high');
  assert.equal(classifyPermission('Bash', { command: 'npm test' }).risk, 'medium');
  assert.equal(classifyPermission('Edit', { file_path: 'src/a.ts' }).kind, 'write');
  assert.equal(classifyPermission('WebFetch', { url: 'https://x' }).kind, 'network');
  assert.equal(classifyPermission('mcp__foo__bar', { a: 1 }).kind, 'other');
});
