import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { Rules } from '../src/rules.js';
import { Store } from '../src/store.js';
import { previewFile, listDir, resolveReadable } from '../src/files.js';
import { workingDiff } from '../src/git.js';
import { createConnector } from '../src/server.js';

function temp(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-regression-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return dir;
}

test('前缀审批：参数词边界，复合命令/替换/重定向回到审批', (t) => {
  const rules = new Rules(temp(t));
  rules.add({ sessionId: 's', tool: 'Bash', match: 'prefix', value: 'npm test' });
  const match = (summary) => rules.match({ sessionId: 's', agent: 'claude', toolName: 'Bash', summary });
  assert.ok(match('npm test --runInBand'));
  for (const cmd of ['npm test-other', 'npm test && echo other', 'npm test; echo other', 'npm test\necho other', 'npm test | cat', 'npm test > file', 'npm test $(echo other)', 'npm test `echo other`', 'npm test "arg"', 'npm test &', 'npm test #comment', 'npm test \\\nother']) assert.equal(match(cmd), null, cmd);
});

test('文件边界：真实路径、目录符号链接、凭据在工作目录内也拒绝', (t) => {
  const dir = temp(t), project = path.join(dir, 'project'), outside = path.join(dir, 'outside');
  fs.mkdirSync(project); fs.mkdirSync(outside);
  fs.writeFileSync(path.join(outside, 'note.txt'), 'outside fixture');
  fs.writeFileSync(path.join(project, 'ok.txt'), 'inside');
  fs.symlinkSync(path.join(outside, 'note.txt'), path.join(project, 'escape.txt'));
  fs.symlinkSync(outside, path.join(project, 'escape-dir'));
  fs.symlinkSync(path.join(project, 'ok.txt'), path.join(project, 'ok-link.txt'));
  fs.mkdirSync(path.join(project, '.ssh'));
  fs.writeFileSync(path.join(project, '.ssh', 'id_rsa'), 'synthetic credential');
  fs.symlinkSync(path.join(project, '.ssh', 'id_rsa'), path.join(project, 'secret-alias'));
  for (const file of ['escape.txt', 'escape-dir/note.txt', '.ssh/id_rsa', 'secret-alias']) {
    assert.throws(() => previewFile(project, file), (e) => e.status === 403, file);
    assert.throws(() => resolveReadable(project, path.join(project, file)), (e) => e.status === 403, file);
  }
  assert.throws(() => listDir(project, 'escape-dir'), (e) => e.status === 403);
  assert.equal(String(previewFile(project, 'ok-link.txt').body), 'inside');
  assert.ok(!listDir(project, '').entries.some((e) => e.name === 'escape.txt'));
});

test('队列恢复：保留暂停、发送中变为待确认、拒绝审批不产生空闲事件', async (t) => {
  const home = temp(t), store = new Store(home);
  const s = store.createSession({ agent: 'mock', cwd: home });
  const q = store.enqueue(s.id, { text: 'first' });
  store.enqueue(s.id, { text: 'second' });
  store.markQueued(s.id, q.id, 'dispatching');
  const recovered = new Store(home), rs = recovered.session(s.id);
  assert.equal(rs.queue.length, 2); assert.equal(rs.queuePaused, true);
  assert.equal(rs.queue[0].deliveryState, 'uncertain');
  assert.throws(() => recovered.resumeQueue(s.id), (e) => e.status === 409);
  recovered.cancelQueued(s.id, q.id); recovered.resumeQueue(s.id);
  assert.equal(rs.queuePaused, false); assert.equal(rs.queue[0].text, 'second');
  const pending = recovered.requestApproval({ sessionId: s.id, kind: 'shell', summary: 'test', toolName: 'Bash', risk: 'medium' });
  assert.equal(recovered.resolveApproval(recovered.approvals[0].id, 'invalid'), false);
  recovered.resolveApproval(recovered.approvals[0].id, 'deny');
  assert.equal(await pending, 'deny'); assert.equal(rs.status, 'running');
});

test('Git：基线后已提交修改、暂存+未暂存、中文重命名、子目录与新文件', async (t) => {
  const dir = temp(t), git = (...args) => execFileSync('git', ['-C', dir, ...args], { encoding: 'utf8' }).trim();
  git('init', '-q'); git('config', 'user.name', 'Test'); git('config', 'user.email', 'test@example.invalid');
  fs.writeFileSync(path.join(dir, '原始.txt'), 'base\n'); git('add', '.'); git('commit', '-qm', 'base');
  const base = git('rev-parse', 'HEAD');
  fs.writeFileSync(path.join(dir, '原始.txt'), 'committed\n'); git('commit', '-qam', 'changed');
  let diff = await workingDiff(dir, { base });
  assert.equal(diff.files.length, 1); assert.match(diff.files[0].diff, /\+committed/);
  fs.writeFileSync(path.join(dir, '原始.txt'), 'staged\n'); git('add', '.');
  fs.writeFileSync(path.join(dir, '原始.txt'), 'unstaged\n');
  diff = await workingDiff(dir);
  assert.match(diff.files[0].diff, /\+staged/); assert.match(diff.files[0].diff, /\+unstaged/);
  git('add', '.'); git('commit', '-qm', 'mixed'); git('mv', '原始.txt', '新名字.txt');
  fs.mkdirSync(path.join(dir, 'nested')); fs.writeFileSync(path.join(dir, 'nested', 'new.txt'), 'new content\n');
  diff = await workingDiff(path.join(dir, 'nested'));
  assert.ok(diff.files.some((f) => f.path === '新名字.txt'));
  assert.ok(diff.files.some((f) => f.path === '原始.txt'));
  assert.match(diff.files.find((f) => f.path === 'nested/new.txt').diff, /\+new content/);
  fs.symlinkSync(path.join(dir, '..'), path.join(dir, 'escape'));
  assert.ok(!(await workingDiff(dir)).files.some((f) => f.path === 'escape'));
});

test('恢复队列接口：需主动继续；停止/Agent 错误会暂停后续发送', async (t) => {
  const home = temp(t); let store = new Store(home);
  const s = store.createSession({ agent: 'mock', cwd: home }); store.enqueue(s.id, { text: 'recover me' });
  const c = await createConnector({ port: 0, home, defaultAgent: 'mock', importTerminal: false, log: () => {} });
  t.after(() => c.close()); const port = await c.listen(); const base = `http://127.0.0.1:${port}`;
  const d = c.store.addDevice('test'), headers = { authorization: `Bearer ${d.token}`, 'content-type': 'application/json' };
  assert.equal(c.store.messagesOf(s.id).length, 0);
  assert.equal(c.store.session(s.id).queuePaused, true);
  const res = await fetch(`${base}/sessions/${s.id}/queue/resume`, { method: 'POST', headers });
  assert.equal(res.status, 200);
  assert.ok(c.store.messagesOf(s.id).some((m) => m.text === 'recover me'));
  c.store.enqueue(s.id, { text: 'later' });
  await fetch(`${base}/sessions/${s.id}/stop`, { method: 'POST', headers });
  assert.equal(c.store.session(s.id).queuePaused, true);
  c.store.setStatus(s.id, 'error'); assert.equal(c.store.session(s.id).queuePaused, true);
});

test('立即发送复用队列消息，保留附件和其它消息，拒绝重复发送', async (t) => {
  const home = temp(t);
  const c = await createConnector({ port: 0, home, defaultAgent: 'mock', importTerminal: false, log: () => {} });
  t.after(() => c.close()); const port = await c.listen();
  const d = c.store.addDevice('test'), headers = { authorization: `Bearer ${d.token}` };
  const s = c.store.createSession({ agent: 'mock', cwd: home, title: 'queue' });
  const first = c.store.enqueue(s.id, { text: 'later' });
  const selected = c.store.enqueue(s.id, { text: 'send first' });
  c.store.pauseQueue(s.id);
  const url = `http://127.0.0.1:${port}/sessions/${s.id}/queue/${selected.id}/send-now`;
  assert.equal((await fetch(url, { method: 'POST', headers })).status, 200);
  assert.equal(c.store.messagesOf(s.id).filter(m => m.role === 'user' && m.text === 'send first').length, 1);
  assert.ok(s.queue.some(q => q.id === first.id));
  assert.ok([404, 409].includes((await fetch(url, { method: 'POST', headers })).status));
  const deadline = Date.now() + 8000;
  while (s.queue.some(q => q.id === selected.id) && Date.now() < deadline) await new Promise(r => setTimeout(r, 20));
  assert.ok(!s.queue.some(q => q.id === selected.id));
  const other = c.store.createSession({ agent: 'mock', cwd: home, title: 'attachments' });
  const q = c.store.enqueue(other.id, { text: 'attachment', attachments: ['image-id'] });
  c.store.prioritizeQueued(other.id, q.id);
  assert.equal(other.queue[0].id, q.id);
  assert.deepEqual(other.queue[0].attachments, ['image-id']);
  c.store.markQueued(other.id, q.id, 'uncertain');
  assert.throws(() => c.store.prioritizeQueued(other.id, q.id), e => e.status === 409);
});
