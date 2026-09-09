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

test('默认端口被占用时自动后移', async () => {
  const net = await import('node:net');
  const blocker = net.createServer(); await new Promise((r) => blocker.listen(0, '0.0.0.0', r));
  const busy = blocker.address().port;
  const c = await createConnector({ port: busy, name: 'T', defaultAgent: 'mock', home: fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-port-')), log: () => {} });
  const got = await c.listen();
  assert.equal(got, busy + 1);
  assert.equal(c.port, busy + 1);
  await c.close(); blocker.close();
});

test('会话选项：新建 / PATCH / WS 切换 / 能力表', async () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-opt-'));
  const c = await createConnector({ port: 0, name: 'T', defaultAgent: 'mock', home, log: () => {} });
  const port = await c.listen();
  const base = `http://127.0.0.1:${port}`;
  const pair = await (await fetch(`${base}/pair`, { method: 'POST', body: JSON.stringify({ token: c.pairing.token }) })).json();
  const H = { authorization: `Bearer ${pair.deviceToken}`, 'content-type': 'application/json' };

  // 能力表
  const caps = await (await fetch(`${base}/agents`, { headers: H })).json();
  assert.deepEqual(Object.keys(caps.claude.modes), ['plan', 'normal', 'trust']);
  assert.ok(caps.claude.efforts.includes('max'));
  assert.ok(caps.codex.models.length > 0);
  assert.equal(caps.codex.customModel, true);

  // 新建：默认 normal；yolo 兼容成 trust；非法 effort 被丢弃
  const s1 = await (await fetch(`${base}/sessions`, { method: 'POST', headers: H, body: JSON.stringify({ agent: 'mock', cwd }) })).json();
  assert.equal(s1.mode, 'normal'); assert.equal(s1.model, null); assert.equal(s1.effort, null);
  const s2 = await (await fetch(`${base}/sessions`, { method: 'POST', headers: H, body: JSON.stringify({ agent: 'mock', cwd, yolo: true, model: 'opus', effort: 'bogus' }) })).json();
  assert.equal(s2.mode, 'trust'); assert.equal(s2.model, 'opus'); assert.equal(s2.effort, null);

  // PATCH → 返回新会话并广播 session.updated
  const ws = new WebSocket(`ws://127.0.0.1:${port}/ws?token=${pair.deviceToken}`);
  const events = [];
  await new Promise((r) => ws.on('open', r));
  ws.on('message', (d) => events.push(JSON.parse(d)));
  const waitFor = (pred, ms = 3000) => new Promise((res, rej) => { const t0 = Date.now(); const tick = () => { const e = events.find(pred); if (e) return res(e); if (Date.now() - t0 > ms) return rej(new Error('timeout')); setTimeout(tick, 20); }; tick(); });
  const patched = await (await fetch(`${base}/sessions/${s1.id}`, { method: 'PATCH', headers: H, body: JSON.stringify({ mode: 'plan', effort: 'high', model: 'sonnet' }) })).json();
  assert.equal(patched.mode, 'plan'); assert.equal(patched.effort, 'high'); assert.equal(patched.model, 'sonnet');
  const ev = await waitFor((e) => e.type === 'session.updated' && e.session.id === s1.id && e.session.mode === 'plan');
  assert.equal(ev.session.effort, 'high');
  // 通过 WS 切换；model 传空串表示恢复默认
  ws.send(JSON.stringify({ type: 'session.configure', sessionId: s1.id, mode: 'trust', model: '' }));
  const ev2 = await waitFor((e) => e.type === 'session.updated' && e.session.id === s1.id && e.session.mode === 'trust');
  assert.equal(ev2.session.model, null); assert.equal(ev2.session.effort, 'high');
  // 持久化后重启仍在
  const listed = await (await fetch(`${base}/sessions/${s1.id}`, { headers: H })).json();
  assert.equal(listed.mode, 'trust');
  ws.close();
  await c.close();
});

test('选项映射到命令行参数', async () => {
  const { claudeOptionArgs, codexOptionArgs, normalizeOptions } = await import('../src/agents/options.js');
  assert.deepEqual(claudeOptionArgs({ mode: 'normal' }), ['--permission-prompt-tool', 'mcp__yzvibe__approve']);
  assert.deepEqual(claudeOptionArgs({ mode: 'plan', model: 'opus', effort: 'max' }), ['--permission-prompt-tool', 'mcp__yzvibe__approve', '--permission-mode', 'plan', '--model', 'opus', '--effort', 'max']);
  assert.deepEqual(claudeOptionArgs({ mode: 'trust' }), ['--dangerously-skip-permissions']);
  assert.ok(codexOptionArgs({ mode: 'plan' }).includes('sandbox_mode="read-only"'));
  assert.ok(codexOptionArgs({ mode: 'trust' }).includes('--dangerously-bypass-approvals-and-sandbox'));
  const cx = codexOptionArgs({ mode: 'normal', model: 'gpt-5.5', effort: 'xhigh' });
  assert.ok(cx.includes('sandbox_mode="workspace-write"') && cx.includes('gpt-5.5') && cx.includes('model_reasoning_effort="xhigh"'));
  assert.deepEqual(normalizeOptions({ mode: 'nope', model: 'a b', effort: 'ultra' }, 'codex'), { effort: 'ultra' });
  assert.deepEqual(normalizeOptions({ yolo: true, model: null }), { mode: 'trust', model: null });
});

test('Codex JSONL 事件 → 消息 / 工具卡', async () => {
  const { handleCodexEvent } = await import('../src/agents/codex.js');
  const { Store } = await import('../src/store.js');
  const store = new Store(fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-cx-')));
  const s = store.createSession({ agent: 'codex', cwd, title: 't' });
  const lines = [
    '{"type":"thread.started","thread_id":"th-1"}',
    '{"type":"turn.started"}',
    '{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"I will run it."}}',
    '{"type":"item.started","item":{"id":"item_2","type":"command_execution","command":"/bin/zsh -lc \'echo hi\'","status":"in_progress"}}',
    '{"type":"item.completed","item":{"id":"item_2","type":"command_execution","command":"/bin/zsh -lc \'echo hi\'","exit_code":0,"status":"completed"}}',
    '{"type":"item.completed","item":{"id":"item_3","type":"file_change","changes":[{"path":"a.ts","kind":"update"}],"status":"completed"}}',
    '{"type":"item.completed","item":{"id":"item_4","type":"agent_message","text":"ok"}}',
    '{"type":"turn.completed","usage":{}}',
  ];
  const state = {};
  for (const l of lines) handleCodexEvent(JSON.parse(l), store, s, state);
  assert.equal(store.session(s.id).agentSessionId, 'th-1');
  const msgs = store.messagesOf(s.id);
  assert.deepEqual(msgs.filter((m) => m.role === 'assistant').map((m) => m.text), ['I will run it.', 'ok']);
  const calls = msgs.flatMap((m) => m.toolCalls);
  assert.deepEqual(calls.map((t) => [t.name, t.detail, t.state]), [['Shell', 'echo hi', 'done'], ['Edit', 'a.ts', 'done']]);
  handleCodexEvent({ type: 'turn.failed', error: { message: '{"error":{"message":"model needs upgrade"}}' } }, store, s, state);
  assert.ok(store.messagesOf(s.id).some((m) => m.role === 'system' && m.text.includes('model needs upgrade')));
  // 下一轮 item id 从 item_1 重新计数，不能追加到上一轮的消息里
  handleCodexEvent({ type: 'turn.started' }, store, s, state);
  handleCodexEvent({ type: 'item.completed', item: { id: 'item_1', type: 'agent_message', text: 'second turn' } }, store, s, state);
  assert.deepEqual(store.messagesOf(s.id).filter((m) => m.role === 'assistant').map((m) => m.text), ['I will run it.', 'ok', 'second turn']);
});

test('目录浏览 / 新建文件夹（选工作目录用）', async () => {
  const c = await createConnector({ port: 0, name: 'T', defaultAgent: 'mock', home: fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-fs-')), log: () => {} });
  const port = await c.listen();
  const base = `http://127.0.0.1:${port}`;
  const pair = await (await fetch(`${base}/pair`, { method: 'POST', body: JSON.stringify({ token: c.pairing.token }) })).json();
  const H = { authorization: `Bearer ${pair.deviceToken}`, 'content-type': 'application/json' };
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-tree-'));
  fs.mkdirSync(path.join(root, 'b')); fs.mkdirSync(path.join(root, 'a')); fs.mkdirSync(path.join(root, '.hidden')); fs.writeFileSync(path.join(root, 'file.txt'), '');
  const dirs = await (await fetch(`${base}/fs/dirs?path=${encodeURIComponent(root)}`, { headers: H })).json();
  assert.deepEqual(dirs.entries.map((e) => e.name), ['a', 'b']);
  assert.equal(dirs.parent, path.dirname(root));
  assert.ok(dirs.home);
  const home = await (await fetch(`${base}/fs/dirs`, { headers: H })).json();
  assert.equal(home.path, os.homedir());
  const mk = await (await fetch(`${base}/fs/mkdir`, { method: 'POST', headers: H, body: JSON.stringify({ parent: root, name: 'new-proj' }) })).json();
  assert.ok(fs.statSync(mk.path).isDirectory());
  assert.equal((await fetch(`${base}/fs/mkdir`, { method: 'POST', headers: H, body: JSON.stringify({ parent: root, name: '../x' }) })).status, 400);
  assert.equal((await fetch(`${base}/fs/dirs?path=${encodeURIComponent(root)}`)).status, 401);
  await c.close();
});
