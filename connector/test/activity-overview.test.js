import test from 'node:test';
import assert from 'node:assert/strict';
import { activityOverview } from '../src/activity-overview.js';
import { createConnector } from '../src/server.js';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

test('island overview caps tasks, prioritizes approvals and stays below APNs payload limit', () => {
  const sessions = Array.from({ length: 12 }, (_, i) => ({ id: `s${i}`, title: '很长的任务标题'.repeat(100), agent: 'codex',
    status: i === 11 ? 'waiting_approval' : 'running', updatedAt: '2026-09-12T10:00:00Z', pendingApprovals: i === 11 ? 1 : 0 }));
  const state = activityOverview(sessions);
  assert.equal(state.totalTasks, 12); assert.equal(state.tasks.length, 3); assert.equal(state.tasks[0].id, 's11');
  assert.ok(Buffer.byteLength(JSON.stringify({ aps: { 'content-state': state } })) < 3500);
  sessions.forEach(s => { s.status = 'idle'; s.queue = [{}]; });
  assert.equal(activityOverview(sessions).totalTasks, 0);
});

test('running clock uses turn start, not latest message time; old sessions retain a fallback', () => {
  const state = activityOverview([{ id: '1', title: 'test', agent: 'claude', status: 'running',
    runStartedAt: '2026-09-12T09:00:00Z', updatedAt: '2026-09-12T10:00:00Z' }]);
  assert.equal(state.startedAt, Date.parse('2026-09-12T09:00:00Z') / 1000 - 978307200);
  assert.equal(state.tasks[0].startedAt, state.startedAt);
});

test('overview token survives one task ending and ends only after the last task', async () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-overview-'));
  const c = await createConnector({ home, port: 0, importTerminal: false, log: () => {} });
  try {
    await c.listen();
    const base = `http://127.0.0.1:${c.port}`;
    const pair = await (await fetch(base + '/pair', { method: 'POST', body: JSON.stringify({ token: c.pairing.token }) })).json();
    const a = c.store.createSession({ agent: 'mock', cwd: home, title: 'one' });
    const b = c.store.createSession({ agent: 'mock', cwd: home, title: 'two' });
    c.store.setStatus(a.id, 'running'); c.store.setStatus(b.id, 'running');
    Object.defineProperty(c.pusher, 'ready', { get: () => true });
    const sent = [];
    c.pusher.sendLiveActivity = async (_, payload) => { sent.push(payload); };
    const id = `overview:${c.store.connector.id}`;
    const r = await fetch(base + '/devices/live-activity', { method: 'POST', headers: { authorization: `Bearer ${pair.deviceToken}` },
      body: JSON.stringify({ sessionId: id, token: 'a'.repeat(64), environment: 'production' }) });
    assert.equal(r.status, 200); assert.equal(sent.at(-1).state.totalTasks, 2);
    c.store.setStatus(a.id, 'idle');
    await new Promise(resolve => setTimeout(resolve, 1350));
    assert.equal(sent.at(-1).event, 'update'); assert.equal(sent.at(-1).state.totalTasks, 1);
    assert.equal(c.store.liveActivitiesFor(id).length, 1);
    c.store.setStatus(b.id, 'idle');
    await new Promise(resolve => setTimeout(resolve, 1350));
    assert.equal(sent.at(-1).event, 'end'); assert.equal(c.store.liveActivitiesFor(id).length, 0);
  } finally { await c.close(); fs.rmSync(home, { recursive: true, force: true }); }
});
