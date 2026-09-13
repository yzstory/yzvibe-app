import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Store } from '../src/store.js';
import { createConnector } from '../src/server.js';

function fixture(t) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'yz-notifications-'));
  t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  const store = new Store(home), s = store.createSession({ agent: 'codex', cwd: home });
  const events = []; store.on('event', e => events.push(e));
  const reply = (id, text, phase) => { store.appendDelta(s.id, id, text); const m = store.messagesOf(s.id).find(m => m.id === id); m.phase = phase; store.finishMessage(s.id, id); };
  return { home, store, s, events, reply };
}

test('multi-part chat is preserved; successful run emits final once, before next queued run', t => {
  const { store, s, events, reply } = fixture(t);
  store.setStatus(s.id, 'running');
  reply('progress', '正在检查', 'commentary'); reply('final', '修复完成', 'final_answer');
  assert.equal(events.filter(e => e.type === 'message.done').length, 2);
  assert.equal(events.filter(e => e.type === 'run.completed').length, 0);
  store.setStatus(s.id, 'idle'); store.setStatus(s.id, 'idle');
  const done = events.filter(e => e.type === 'run.completed');
  assert.equal(done.length, 1); assert.equal(done[0].text, '修复完成'); assert.equal(done[0].messageId, 'final');
  assert.equal(store.messagesOf(s.id).length, 2);
  store.setStatus(s.id, 'running'); store.setStatus(s.id, 'idle');
  assert.equal(events.filter(e => e.type === 'run.completed').length, 1, 'never notify previous run text');
});

test('failed, interrupted and commentary-only runs do not notify; legacy Claude uses last reply', t => {
  const { store, s, events, reply } = fixture(t);
  for (const [i, status] of ['error', 'closed', 'idle'].entries()) {
    store.setStatus(s.id, 'running'); reply(`m${i}`, '进度', 'commentary'); store.setStatus(s.id, status);
  }
  store.setStatus(s.id, 'running'); reply('stopped', 'partial'); s.stopRequested = true; store.setStatus(s.id, 'idle');
  assert.equal(events.filter(e => e.type === 'run.completed').length, 0);
  store.setStatus(s.id, 'running'); reply('c1', 'Working'); reply('c2', 'Done'); store.setStatus(s.id, 'idle');
  assert.equal(events.find(e => e.type === 'run.completed').text, 'Done');
});

test('notification preferences persist per phone and survive push registration', t => {
  const { home, store } = fixture(t); const d = store.addDevice('phone');
  store.setNotificationPreferences(d.id, { notifyOnReply: false, notifyOnApproval: true });
  store.setDevicePush(d.id, { token: 'abc' }); store.setDevicePush(d.id, null);
  assert.equal(new Store(home).devices.find(x => x.id === d.id).notificationPreferences.notifyOnReply, false);
});

test('authenticated preference endpoint affects only caller; server pushes only run completion', async t => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'yz-notify-api-'));
  const c = await createConnector({ home, port: 0, importTerminal: false, log: () => {} });
  await c.listen();
  t.after(async () => { await c.close(); fs.rmSync(home, { recursive: true, force: true }); });
  const phone = c.store.addDevice('phone'), other = c.store.addDevice('other');
  const url = `http://127.0.0.1:${c.port}/devices/notifications`;
  const body = JSON.stringify({ notifyOnReply: false, notifyOnApproval: true });
  assert.equal((await fetch(url, { method: 'PATCH', body })).status, 401);
  const headers = { Authorization: `Bearer ${phone.token}`, 'Content-Type': 'application/json' };
  assert.equal((await fetch(url, { method: 'PATCH', headers, body: JSON.stringify({ notifyOnReply: 'false' }) })).status, 400);
  assert.equal((await fetch(url, { method: 'PATCH', headers, body })).status, 200);
  assert.equal(phone.notificationPreferences.notifyOnReply, false); assert.equal(other.notificationPreferences, undefined);
  c.pusher.config.ready = true;
  const sent = []; c.pusher.send = async (devices, note) => { sent.push(note); return []; };
  const s = c.store.createSession({ agent: 'codex', cwd: home }); c.store.setStatus(s.id, 'running');
  for (const [id, text] of [['p', 'progress'], ['f', 'final']]) { c.store.appendDelta(s.id, id, text); c.store.finishMessage(s.id, id); }
  assert.equal(sent.length, 0);
  c.store.setStatus(s.id, 'idle'); c.store.setStatus(s.id, 'idle');
  assert.equal(sent.length, 1); assert.equal(sent[0].data.messageId, 'f'); assert.match(sent[0].body, /final$/);
});
