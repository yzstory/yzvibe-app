import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import http from 'node:http';
import { once } from 'node:events';
import { WebSocket } from 'ws';
import { Store } from '../src/store.js';
import { createConnector } from '../src/server.js';
import { diagnostics } from '../src/diagnostics.js';
import { JSON_LIMIT } from '../src/requests.js';
import { runCleanup } from '../src/cleanup.js';

function temporary(t) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-delivery-'));
  t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  return home;
}
async function fixture(t) {
  const home = temporary(t);
  const connector = await createConnector({ home, port: 0, defaultAgent: 'mock', importTerminal: false, log: () => {} });
  await connector.listen(); t.after(() => connector.close());
  const device = connector.store.addDevice('fixture');
  const base = `http://127.0.0.1:${connector.port}`;
  const call = (url, body, method = body ? 'POST' : 'GET') => fetch(base + url, { method, headers: { authorization: `Bearer ${device.token}`, 'content-type': 'application/json' }, ...(body ? { body: JSON.stringify(body) } : {}) });
  const s = connector.store.createSession({ agent: 'mock', cwd: home, title: 'fixture' });
  return { connector, device, base, call, s };
}
const waitFor = async predicate => {
  for (let i = 0; i < 150; i++) { if (predicate()) return; await new Promise(r => setTimeout(r, 30)); }
  assert.fail('condition timed out');
};

test('durable deltas recover text and interrupted state; stale journals cannot overwrite authoritative text', t => {
  const home = temporary(t), store = new Store(home);
  const s = store.createSession({ agent: 'mock', cwd: home, title: 'fixture' });
  store.setStatus(s.id, 'running');
  store.appendDelta(s.id, 'm', '你好🙂 a long streaming response');
  const journalPath = path.join(home, 'messages', `${s.id}.jsonl`);
  const journal = fs.readFileSync(journalPath);
  runCleanup(store);
  assert.ok(fs.statSync(journalPath).size > 0, 'cleanup keeps the active journal');
  const recovered = new Store(home);
  assert.equal(recovered.messagesOf(s.id).find(m => m.id === 'm').text, '你好🙂 a long streaming response');
  assert.equal(recovered.messagesOf(s.id).find(m => m.id === 'm').streaming, false);
  assert.equal(recovered.session(s.id).status, 'error');
  assert.equal(recovered.runsOf(s.id)[0].status, 'interrupted');
  recovered.replaceMessageText(s.id, 'm', 'short');
  fs.writeFileSync(journalPath, journal); // Simulate a crash between snapshot rename and journal truncation.
  assert.equal(new Store(home).messagesOf(s.id).find(m => m.id === 'm').text, 'short');
});

test('receipt and queue commit together, retain ID across restart and never re-dispatch uncertain work', t => {
  const home = temporary(t), store = new Store(home);
  const s = store.createSession({ agent: 'mock', cwd: home, title: 'fixture' });
  const input = { clientMessageId: 'durable-message-1', text: 'once', attachments: [], mode: 'auto' };
  const accepted = store.acceptMessage(s.id, input);
  assert.equal(store.acceptMessage(s.id, input).itemId, accepted.itemId);
  assert.equal(s.queue.length, 1);
  assert.throws(() => store.acceptMessage(s.id, { ...input, text: 'different' }), e => e.status === 409);
  store.markQueued(s.id, accepted.itemId, 'dispatching');
  const recovered = new Store(home);
  assert.equal(recovered.receipt(s.id, input.clientMessageId).state, 'uncertain');
  assert.equal(recovered.session(s.id).queuePaused, true);
  assert.throws(() => recovered.resumeQueue(s.id), e => e.status === 409);
  recovered.cancelQueued(s.id, accepted.itemId);
  assert.equal(recovered.acceptMessage(s.id, input).state, 'uncertain');
  assert.equal(recovered.session(s.id).queue.length, 0);
});

test('lost HTTP response and concurrent retries share one delivery and one task run', async t => {
  const { connector, call, s } = await fixture(t);
  const input = { clientMessageId: 'http-message-1', text: 'fixture task', attachments: [], mode: 'auto' };
  const responses = await Promise.all(Array.from({ length: 5 }, () => call(`/sessions/${s.id}/deliveries`, input)));
  assert.ok(responses.every(r => r.status === 202));
  await waitFor(() => connector.store.receipt(s.id, input.clientMessageId)?.state === 'sent');
  const receipt = await (await call(`/sessions/${s.id}/deliveries/${input.clientMessageId}`)).json();
  assert.equal(receipt.state, 'sent');
  assert.equal('fingerprint' in receipt, false);
  assert.equal(connector.store.messagesOf(s.id).filter(m => m.clientMessageId === input.clientMessageId).length, 1);
  assert.equal(connector.store.runsOf(s.id).length, 1);
  assert.equal((await call(`/sessions/${s.id}/deliveries`, { ...input, text: 'changed' })).status, 409);
});

test('failed receipt commit cannot be mistaken for a durable acceptance', t => {
  const home = temporary(t), store = new Store(home);
  const s = store.createSession({ agent: 'mock', cwd: home, title: 'fixture' });
  const input = { clientMessageId: 'disk-failure-1', text: 'keep on phone', attachments: [], mode: 'auto' };
  const rename = fs.renameSync;
  fs.renameSync = () => { throw Object.assign(new Error('disk full'), { code: 'ENOSPC' }); };
  try { assert.throws(() => store.acceptMessage(s.id, input), /disk full/); }
  finally { fs.renameSync = rename; }
  assert.equal(store.receipt(s.id, input.clientMessageId), null);
  assert.equal(s.queue.length, 0);
  assert.equal(new Store(home).receipt(s.id, input.clientMessageId), null);
  assert.equal(store.acceptMessage(s.id, input).state, 'queued');
  assert.equal(s.queue.length, 1);
});

test('all attachments validate before accepting a message', async t => {
  const { connector, call, s } = await fixture(t);
  const good = connector.store.addUpload('fixture.png', 'image/png', Buffer.from([1]));
  const input = { clientMessageId: 'image-message-1', text: 'read both', attachments: [good, 'missing-image'], mode: 'auto' };
  const response = await call(`/sessions/${s.id}/deliveries`, input);
  assert.equal(response.status, 422);
  assert.equal((await response.json()).code, 'attachment_missing');
  assert.equal(s.queue.length, 0);
  assert.equal(connector.store.receipt(s.id, input.clientMessageId), null);
  for (const invalid of [{ text: 3 }, { attachments: 'not-array' }, { mode: 'never' }, { text: 'x'.repeat(64_001) }]) {
    assert.equal((await call(`/sessions/${s.id}/deliveries`, { ...input, attachments: [], ...invalid })).status, 400);
  }
});

test('reconnected WS snapshot contains missed updates and precedes subsequent live events', async t => {
  const { connector, device, base, s } = await fixture(t);
  connector.store.appendDelta(s.id, 'reply', 'before offline');
  const connect = () => {
    const socket = new WebSocket(base.replace('http:', 'ws:') + `/ws?token=${device.token}`);
    const events = []; socket.on('message', raw => events.push(JSON.parse(raw)));
    t.after(() => socket.terminate()); return { socket, events };
  };
  const first = connect(); await once(first.socket, 'open'); first.socket.close(); await once(first.socket, 'close');
  connector.store.appendDelta(s.id, 'reply', ' + during offline');
  connector.store.upsertToolCall(s.id, { id: 'tool', name: 'Shell', detail: 'fixture', state: 'done', output: 'evidence', exitCode: 0 }, 'reply');
  const second = connect(); await once(second.socket, 'open');
  second.socket.send(JSON.stringify({ type: 'sync.request', sessionIds: [s.id] }));
  await waitFor(() => second.events.some(e => e.type === 'sync.snapshot'));
  connector.store.appendDelta(s.id, 'reply', ' + live again');
  await waitFor(() => second.events.some(e => e.type === 'message.delta'));
  const snap = second.events.find(e => e.type === 'sync.snapshot');
  assert.equal(snap.messages[s.id][0].text, 'before offline + during offline');
  assert.equal(snap.messages[s.id][0].toolCalls[0].output, 'evidence');
  assert.ok(second.events.findIndex(e => e.type === 'sync.snapshot') < second.events.findIndex(e => e.type === 'message.delta'));
});

test('oversized public JSON and chunked body reject early; malformed WS leaves service healthy', async t => {
  const { base, device, call } = await fixture(t);
  assert.equal((await fetch(base + '/pair', { method: 'POST', body: 'x'.repeat(JSON_LIMIT + 1) })).status, 413);
  const status = await new Promise((resolve, reject) => {
    const request = http.request(base + '/pair', { method: 'POST' }, response => { response.resume(); resolve(response.statusCode); });
    request.on('error', reject);
    request.write('x'.repeat(JSON_LIMIT)); request.end('too much');
  });
  assert.equal(status, 413);
  const socket = new WebSocket(base.replace('http:', 'ws:') + `/ws?token=${device.token}`);
  socket.on('error', () => {}); t.after(() => socket.terminate());
  await once(socket, 'open');
  socket.send('null'); socket.send('x'.repeat(JSON_LIMIT + 1));
  const [code] = await once(socket, 'close'); assert.equal(code, 1009);
  assert.equal((await call('/health')).status, 200);
});

test('ordered snapshot adopts a terminal session and includes its existing transcript', async t => {
  const home = temporary(t), claudeHome = path.join(home, 'claude');
  const project = path.join(claudeHome, 'projects', 'fixture'); fs.mkdirSync(project, { recursive: true });
  const terminalID = '11111111-2222-3333-4444-555555555555';
  fs.writeFileSync(path.join(project, `${terminalID}.jsonl`), [
    { type: 'user', cwd: home, sessionId: terminalID, uuid: 'user', timestamp: new Date().toISOString(), message: { role: 'user', content: 'existing terminal prompt' } },
    { type: 'assistant', uuid: 'reply', timestamp: new Date().toISOString(), message: { id: 'reply', role: 'assistant', content: [{ type: 'text', text: 'existing terminal reply' }] } },
  ].map(JSON.stringify).join('\n'));
  const connector = await createConnector({ home: path.join(home, 'store'), port: 0, defaultAgent: 'mock', claudeHome, codexHome: path.join(home, 'codex'), log: () => {} });
  await connector.listen(); t.after(() => connector.close());
  const device = connector.store.addDevice('fixture');
  const socket = new WebSocket(`ws://127.0.0.1:${connector.port}/ws?token=${device.token}`);
  const events = []; socket.on('message', raw => events.push(JSON.parse(raw))); t.after(() => socket.terminate());
  await once(socket, 'open');
  socket.send(JSON.stringify({ type: 'sync.request', sessionIds: [`claude:${terminalID}`] }));
  await waitFor(() => events.some(e => e.type === 'sync.snapshot'));
  const snap = events.find(e => e.type === 'sync.snapshot');
  assert.ok(snap.messages[`claude:${terminalID}`]?.some(m => m.text === 'existing terminal reply'));
});

test('task delivery records observed output and failures without inventing passing tests', t => {
  const store = new Store(temporary(t));
  const s = store.createSession({ agent: 'mock', cwd: '/fixture', title: 'fixture' });
  store.setStatus(s.id, 'running');
  store.upsertToolCall(s.id, { id: 'test', name: 'Shell', detail: 'npm test', state: 'error', output: '1 failing test', exitCode: 1 });
  store.upsertToolCall(s.id, { id: 'edit', name: 'Edit', detail: 'a.js', files: ['a.js'], state: 'done', output: '+fixed', outputKind: 'diff' });
  store.appendDelta(s.id, 'summary', 'The assistant says it finished'); store.finishMessage(s.id, 'summary');
  store.setStatus(s.id, 'idle');
  const run = store.runsOf(s.id)[0];
  assert.equal(run.status, 'completed');
  assert.equal(run.tools[0].exitCode, 1);
  assert.equal(run.tools[0].state, 'error');
  assert.deepEqual(run.files, ['a.js']);
  assert.ok(run.endedAt);
  assert.equal(new Store(store.home).runsOf(s.id)[0].tools[0].output, '1 failing test');
});

test('diagnostics exports only allowlisted facts, never tokens, names, paths or session bodies', async t => {
  const store = new Store(temporary(t));
  const device = store.addDevice('SECRET-NAME'); device.push = { token: 'SECRET-PUSH' };
  store.createSession({ agent: 'mock', cwd: '/SECRET-PATH', title: 'SECRET-TEXT' });
  const result = await diagnostics({ version: '0.1.1', store, device, pusher: { ready: true },
    probeAgent: async id => ({ id, available: true, version: '1.2.3', authentication: 'unchecked' }) });
  const encoded = JSON.stringify(result);
  for (const secret of ['SECRET', device.token, store.home]) assert.equal(encoded.includes(secret), false);
  assert.equal(result.storage.sessions, 1); assert.equal(result.push.registered, true);
});

test('execution index stores references, hydrates on demand and retains only 50 rounds', t => {
  const store = new Store(temporary(t));
  const s = store.createSession({ agent: 'mock', cwd: '/fixture', title: 'fixture' });
  for (let i = 0; i < 52; i++) {
    store.setStatus(s.id, 'running');
    store.upsertToolCall(s.id, { id: `tool-${i}`, name: 'Shell', detail: 'npm test', state: 'done', output: `output-${i}`, exitCode: 0 });
    store.setStatus(s.id, 'idle');
  }
  assert.equal(s.runs.length, 50);
  assert.ok(s.runs.every(r => !('tools' in r) && !('summary' in r)));
  const index = store.runIndex(s.id);
  assert.ok(index.every(r => r.tools.length === 0 && r.summary === ''));
  assert.equal(store.runDetail(s.id, index.at(-1).id).tools[0].output, 'output-51');
  assert.ok(store.messagesOf(s.id).some(m => m.toolCalls.some(t => t.id === 'tool-0')));
  // Simulate an old version's duplicated payload, then migrate without losing output.
  s.runs[0] = store.runDetail(s.id, s.runs[0].id);
  fs.writeFileSync(path.join(store.home, 'sessions.json'), JSON.stringify(store.sessions));
  const recovered = new Store(store.home);
  assert.equal(recovered.session(s.id).runs[0].tools, undefined);
  assert.equal(recovered.runDetail(s.id, index[0].id).tools[0].output, 'output-2');
});

test('execution list excludes output, individual details and legacy API retain it', async t => {
  const { connector, call, s } = await fixture(t);
  connector.store.setStatus(s.id, 'running');
  connector.store.upsertToolCall(s.id, { id: 'check', name: 'Shell', state: 'done', output: 'RESULT', detail: 'npm test' });
  connector.store.setStatus(s.id, 'idle');
  const index = await (await call(`/sessions/${s.id}/runs?summary=1`)).json();
  assert.deepEqual(index[0].tools, []);
  const detail = await (await call(`/sessions/${s.id}/runs/${index[0].id}`)).json();
  assert.equal(detail.tools[0].output, 'RESULT');
  const legacy = await (await call(`/sessions/${s.id}/runs`)).json();
  assert.equal(legacy[0].tools[0].output, 'RESULT');
  assert.equal((await call(`/sessions/${s.id}/runs/missing`)).status, 404);
});
