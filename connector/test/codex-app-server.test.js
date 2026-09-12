import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { PassThrough } from 'node:stream';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Store } from '../src/store.js';
import { CodexAgent, appServerOptions } from '../src/agents/codex-app-server.js';
import { CodexRPC } from '../src/agents/codex-rpc.js';

const tick = () => new Promise(resolve => setImmediate(resolve));
class FakeRPC extends EventEmitter {
  calls = []; replies = []; closed = false; turn = 0;
  async request(method, params) {
    this.calls.push({ method, params });
    if (method === 'thread/start' || method === 'thread/resume') return { thread: { id: params.threadId ?? 'new-thread' }, model: 'test-model', reasoningEffort: 'medium' };
    if (method === 'turn/start') {
      const turn = { id: `turn-${++this.turn}`, status: 'inProgress' };
      this.emit('notification', { method: 'turn/started', params: { threadId: this.threadId, turn } });
      return { turn };
    }
    return {};
  }
  notify(method, params) { this.calls.push({ method, params }); }
  respond(id, result) { this.replies.push({ id, result }); }
  reject(id, message) { this.replies.push({ id, error: message }); }
  close() { this.closed = true; this.emit('disconnect', new Error('closed')); this.removeAllListeners(); }
}
function fixture(t, thread = null) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-appserver-test-'));
  const store = new Store(home), session = store.createSession({ agent: 'codex', cwd: home, mode: 'normal' });
  session.agentSessionId = thread;
  const rpc = new FakeRPC(); rpc.threadId = thread ?? 'new-thread';
  const agent = new CodexAgent({ session, store, rpcFactory: () => { rpc.closed = false; return rpc; }, interruptTimeout: 40 });
  t.after(() => { agent.dispose(); fs.rmSync(home, { recursive: true, force: true }); });
  const event = (method, params = {}) => rpc.emit('notification', { method, params: { threadId: rpc.threadId, turnId: `turn-${rpc.turn}`, ...params } });
  const request = (id, method, params = {}) => rpc.emit('request', { id, method, params: { threadId: rpc.threadId, turnId: `turn-${rpc.turn}`, itemId: 'tool', ...params } });
  const finish = (status = 'completed') => event('turn/completed', { turn: { id: `turn-${rpc.turn}`, status } });
  return { agent, rpc, session, store, event, request, finish };
}

test('new and legacy threads send separate text/image inputs, retaining options and thread identity', async t => {
  for (const thread of [null, 'old-exec-thread']) {
    const f = fixture(t, thread);
    const upload = f.store.addUpload('one.png', 'image/png', Buffer.from('image'));
    await f.agent.send('--help\n中文提示', [upload]);
    assert.equal(f.rpc.calls[0].method, 'initialize');
    assert.equal(f.rpc.calls[1].method, 'initialized');
    assert.equal(f.rpc.calls[2].method, thread ? 'thread/resume' : 'thread/start');
    const p = f.rpc.calls.find(c => c.method === 'turn/start').params;
    assert.equal(p.input[0].text, '--help\n中文提示'); assert.equal(p.input[1].type, 'localImage');
    assert.equal(p.approvalPolicy, 'on-request'); assert.equal(p.sandboxPolicy.type, 'workspaceWrite');
    assert.equal(f.session.agentSessionId, thread ?? 'new-thread');
    await assert.rejects(f.agent.send('duplicate'), /正忙/);
    f.finish(); f.session.mode = 'plan'; await f.agent.send('next');
    assert.equal(f.rpc.calls.at(-1).params.sandboxPolicy.type, 'readOnly');
    assert.match(f.rpc.calls.at(-1).params.input[0].text, /规划模式/);
    assert.equal(f.rpc.calls.filter(c => c.method === 'initialize').length, 2);
  }
});

test('streamed content, authoritative final text, tool ordering and duplicate/late events', async t => {
  const f = fixture(t); await f.agent.send('go');
  f.event('item/agentMessage/delta', { itemId: 'text', delta: '你好' });
  assert.equal(f.store.messagesOf(f.session.id)[0].text, '你好');
  const done = { item: { id: 'text', type: 'agentMessage', text: '你好世界' } };
  f.event('item/completed', done); f.event('item/completed', done);
  assert.equal(f.store.messagesOf(f.session.id)[0].text, '你好世界');
  f.event('item/completed', { item: { id: 'tool', type: 'commandExecution', command: 'pwd', exitCode: 0 } });
  f.event('item/completed', { item: { id: 'text2', type: 'agentMessage', text: 'end' } });
  const list = f.store.messagesOf(f.session.id);
  assert.equal(list[1].toolCalls[0].detail, 'pwd'); assert.equal(list[2].text, 'end');
  f.finish(); await f.agent.send('second');
  f.event('item/agentMessage/delta', { turnId: 'turn-1', itemId: 'text', delta: 'late' });
  f.event('item/agentMessage/delta', { itemId: 'text', delta: 'draft' });
  f.event('item/completed', { item: { id: 'text', type: 'agentMessage', text: 'corrected' } });
  assert.equal(list.at(-1).text, 'corrected'); assert.equal(list[0].text, '你好世界');
});

test('phone allow/deny, multiple pending approvals and expired request ids are isolated', async t => {
  const f = fixture(t); await f.agent.send('go');
  f.request(9, 'item/commandExecution/requestApproval', { command: 'pwd', reason: 'test' });
  f.request(10, 'item/fileChange/requestApproval', { reason: 'edit' });
  assert.equal(f.session.pendingApprovals, 2);
  let [file, shell] = f.store.approvals;
  f.store.resolveApproval(shell.id, 'allow'); await tick();
  assert.equal(f.session.status, 'waiting_approval');
  assert.deepEqual(f.rpc.replies[0], { id: 9, result: { decision: 'accept' } });
  f.store.resolveApproval(file.id, 'deny'); await tick();
  assert.equal(f.session.status, 'running');
  assert.deepEqual(f.rpc.replies[1], { id: 10, result: { decision: 'decline' } });
  f.request(11, 'item/commandExecution/requestApproval', { command: 'pwd' });
  const pending = f.store.approvals[0]; f.finish(); await tick();
  assert.equal(f.session.pendingApprovals, 0); assert.equal(f.session.status, 'idle');
  assert.equal(f.store.resolveApproval(pending.id, 'allow'), false);
  assert.equal(f.rpc.replies.length, 2);
});

test('permissions grant only requested scope; user input requires real answers, never a bare allow', async t => {
  const f = fixture(t); await f.agent.send('go');
  const permissions = { network: { enabled: true } };
  f.request(1, 'item/permissions/requestApproval', { permissions });
  f.store.resolveApproval(f.store.approvals[0].id, 'allow'); await tick();
  assert.deepEqual(f.rpc.replies[0].result, { permissions, scope: 'turn' });
  f.request(2, 'item/tool/requestUserInput', { questions: [{ id: 'color', header: 'Color', question: 'Which color?' }] });
  const a = f.store.approvals[0];
  assert.equal(f.store.resolveApproval(a.id, 'allow'), false);
  assert.equal(f.store.resolveApproval(a.id, 'allow', 'phone', null, { color: 'orange' }), true); await tick();
  assert.deepEqual(f.rpc.replies[1].result, { answers: { color: { answers: ['orange'] } } });
});

test('interrupt waits for completion before advancing queue; transport failure preserves pending work', async t => {
  const f = fixture(t); await f.agent.send('go');
  f.request(1, 'item/commandExecution/requestApproval', { command: 'pwd' });
  f.store.enqueue(f.session.id, { text: 'next' }); f.agent.stop();
  assert.equal(f.rpc.calls.at(-1).method, 'turn/interrupt');
  assert.notEqual(f.session.status, 'idle');
  f.finish('interrupted'); assert.equal(f.session.status, 'idle');
  await f.agent.send('go'); f.rpc.close(); await tick();
  assert.equal(f.session.status, 'error'); assert.equal(f.session.queuePaused, true);
  assert.equal(f.session.queue.length, 1); assert.equal(f.session.pendingApprovals, 0);
});

test('unconfirmed interrupts fail closed and never start the next queued command', async t => {
  const f = fixture(t); await f.agent.send('go'); f.store.enqueue(f.session.id, { text: 'next' }); f.agent.stop();
  await new Promise(resolve => setTimeout(resolve, 60));
  assert.equal(f.session.status, 'error'); assert.equal(f.session.queuePaused, true);
});

test('usage deduplicates updates, separates per-turn totals and reads last-call context directly', async t => {
  const f = fixture(t); await f.agent.send('go');
  const last = { inputTokens: 69950, cachedInputTokens: 60000, outputTokens: 86, reasoningOutputTokens: 10, totalTokens: 70036 };
  const tokenUsage = { last, total: { ...last, inputTokens: 500000, cachedInputTokens: 420000 }, modelContextWindow: 258400 };
  f.event('thread/tokenUsage/updated', { tokenUsage }); f.event('thread/tokenUsage/updated', { tokenUsage });
  assert.equal(f.session.usage.total.turns, 1); assert.equal(f.session.usage.turn.input, 9950);
  assert.equal(f.store.publicSession(f.session).usage.turn.contextTokens, 70036);
  assert.equal(f.session.usage.turn.contextWindow, 258400);
  f.finish(); await f.agent.send('go'); f.event('thread/tokenUsage/updated', { tokenUsage });
  assert.equal(f.session.usage.total.turns, 2); assert.equal(f.session.usage.total.output, 172);
});

test('sandbox modes explicitly preserve trust and read-only semantics', () => {
  assert.equal(appServerOptions({ mode: 'trust' }).approvalPolicy, 'never');
  assert.equal(appServerOptions({ mode: 'trust' }).sandboxPolicy.type, 'dangerFullAccess');
  assert.equal(appServerOptions({ mode: 'plan' }).sandboxPolicy.type, 'readOnly');
});

test('startup disconnect cannot acknowledge or remove a queued send', async t => {
  const f = fixture(t);
  f.rpc.request = async () => { f.rpc.close(); throw new Error('startup failed'); };
  await assert.rejects(f.agent.send('keep this'), /startup failed/);
  assert.equal(f.session.status, 'error');
});

test('turn completed before start response still acknowledges delivery exactly once', async t => {
  const f = fixture(t), original = f.rpc.request.bind(f.rpc);
  f.rpc.request = async (method, params) => {
    const result = await original(method, params);
    if (method === 'turn/start') { f.finish(); throw new Error('late response lost'); }
    return result;
  };
  await f.agent.send('sent'); assert.equal(f.session.status, 'idle');
});

test('generated images use a downloadable attachment and resolved server requests cannot be approved later', async t => {
  const f = fixture(t); await f.agent.send('image');
  f.event('item/completed', { item: { id: 'image', type: 'imageGeneration', status: 'completed', result: 'aW1hZ2U=' } });
  const text = f.store.messagesOf(f.session.id).at(-1).text;
  assert.match(text, /codex-generated.png/); assert.doesNotMatch(text, /data:image/);
  f.request('request-string-id', 'item/commandExecution/requestApproval', { command: 'pwd' });
  const pending = f.store.approvals[0]; f.event('serverRequest/resolved', { requestId: 'request-string-id' }); await tick();
  assert.equal(f.store.resolveApproval(pending.id, 'allow'), false);
  assert.equal(f.rpc.replies.length, 0);
});

test('stdio JSON-RPC handles split UTF-8, out of order replies and pending request disconnect', async () => {
  const child = new EventEmitter(); child.stdin = new PassThrough(); child.stdout = new PassThrough(); child.stderr = new PassThrough(); child.kill = () => {};
  const rpc = new CodexRPC({ cwd: '/tmp', spawnProcess: () => child });
  const a = rpc.request('a', {}), b = rpc.request('b', {});
  const events = []; rpc.on('notification', e => events.push(e));
  const data = Buffer.from(JSON.stringify({ method: 'text', params: { text: '你好' } }) + '\n');
  for (const byte of data) child.stdout.write(Buffer.from([byte]));
  child.stdout.write('{"id":2,"result":"second"}\n{"id":1,"result":"first"}\n');
  assert.deepEqual(await Promise.all([a, b]), ['first', 'second']); assert.equal(events[0].params.text, '你好');
  const pending = rpc.request('unknown', {}); rpc.close(); await assert.rejects(pending, /停止/);
});


test('documents use a readable local path rather than localImage or inline binary input', async t => {
  const f = fixture(t);
  const file = f.store.addUpload('需求.pdf', 'application/pdf', Buffer.from('%PDF-1.7'));
  const image = f.store.addUpload('photo.jpg', 'image/jpeg', Buffer.from('image'));
  await f.agent.send('查看附件', [file, image]);
  const input = f.rpc.calls.find(c => c.method === 'turn/start').params.input;
  assert.equal(input.filter(i => i.type === 'localImage').length, 1);
  const document = input.find(i => i.type === 'text' && i.text.includes('需求.pdf'));
  assert.ok(document); assert.ok(document.text.includes(f.store.upload(file).path));
  assert.equal(document.text.includes('%PDF'), false);
});
