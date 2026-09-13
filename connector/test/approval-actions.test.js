import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Store } from '../src/store.js';
import { Rules } from '../src/rules.js';
import { createConnector } from '../src/server.js';

function fixture(t) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-approval-actions-'));
  const store = new Store(home); store.rules = new Rules(home);
  const session = store.createSession({ agent: 'codex', cwd: home, mode: 'normal' });
  t.after(() => { for (const a of store.approvals) store.resolveApproval(a.id, 'deny'); fs.rmSync(home, { recursive: true, force: true }); });
  const ask = (extra = {}) => store.requestApproval({ sessionId: session.id, agent: 'codex', kind: 'write', toolName: 'Edit', summary: 'file.js', detail: 'edit', risk: 'medium', ...extra });
  return { home, store, session, ask };
}

test('always allow persists a session rule, matches later edits and can be revoked', async t => {
  const { home, store, session, ask } = fixture(t);
  const first = ask(), card = store.approvals[0];
  const suggestion = card.suggestions.find(s => s.ttlMinutes === null);
  assert.ok(suggestion);
  store.resolveApproval(card.id, 'allow', 'phone', suggestion);
  assert.equal(await first, 'allow');
  const rules = new Rules(home); assert.equal(rules.all(session.id).length, 1);
  store.rules = rules;
  assert.equal(await ask({ summary: 'second.js' }), 'allow');
  const rule = rules.all()[0]; assert.equal(rule.hits, 1);
  rules.remove(rule.id);
  const again = ask(); assert.equal(store.approvals[0].status, 'pending');
  store.resolveApproval(store.approvals[0].id, 'deny'); assert.equal(await again, 'deny');
});

test('failed rule save keeps the approval pending and leaves no phantom rule', async t => {
  const { store, ask } = fixture(t);
  const pending = ask(), card = store.approvals[0];
  store.rules.save = () => { throw new Error('disk full'); };
  assert.throws(() => store.resolveApproval(card.id, 'allow', 'phone', card.suggestions[0]), /disk full/);
  assert.equal(card.status, 'pending'); assert.equal(store.rules.list.length, 0);
  store.resolveApproval(card.id, 'deny'); assert.equal(await pending, 'deny');
});

test('Trust handles current permission cards, preserves questions and isolates other sessions', async t => {
  const { store, session, ask } = fixture(t);
  const first = ask(); const firstID = store.approvals[0].id;
  const second = ask({ kind: 'shell', toolName: 'Bash', summary: 'pwd' });
  const question = ask({ questions: [{ id: 'q', question: 'Which option?' }], allowRules: false });
  const questionID = store.approvals[0].id;
  const other = store.createSession({ agent: 'codex', cwd: '/tmp', mode: 'normal' });
  const elsewhere = ask({ sessionId: other.id }); const otherID = store.approvals[0].id;
  assert.equal(store.trustApproval(questionID), null); assert.equal(session.mode, 'normal');
  const result = store.trustApproval(firstID);
  assert.equal(result.session.mode, 'trust'); assert.equal(result.approvals.length, 2);
  assert.equal(await first, 'allow'); assert.equal(await second, 'allow');
  assert.equal(store.approval(questionID).status, 'pending'); assert.equal(store.approval(otherID).status, 'pending');
  assert.equal(other.mode, 'normal'); assert.equal(session.pendingApprovals, 1);
  assert.equal(await ask({ allowRules: false, toolName: 'CodexPermissions' }), 'allow');
  store.configureSession(session.id, { mode: 'normal' });
  assert.equal(store.trustApproval(firstID), null); assert.equal(session.mode, 'normal');
  const normalAgain = ask(); store.resolveApproval(store.approvals[0].id, 'deny'); assert.equal(await normalAgain, 'deny');
  store.resolveApproval(questionID, 'deny'); store.resolveApproval(otherID, 'deny');
  await Promise.all([question, elsewhere]);
});

test('expired approvals and failed persistence never enable Trust', async t => {
  const { store, session, ask } = fixture(t);
  const pending = ask(), card = store.approvals[0];
  const expiry = card.expiresAt; card.expiresAt = new Date(0).toISOString();
  assert.equal(store.trustApproval(card.id), null); assert.equal(session.mode, 'normal');
  card.expiresAt = expiry;
  const configure = store.configureSession.bind(store);
  store.configureSession = () => { session.mode = 'trust'; throw new Error('disk full'); };
  assert.throws(() => store.trustApproval(card.id), /disk full/);
  assert.equal(session.mode, 'normal'); assert.equal(card.status, 'pending');
  store.configureSession = configure;
  store.resolveApproval(card.id, 'deny'); assert.equal(await pending, 'deny');
});

test('trust endpoint requires authentication and returns the committed session', async t => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-trust-http-'));
  const connector = await createConnector({ home, port: 0, defaultAgent: 'mock', importTerminal: false, log: () => {} });
  await connector.listen();
  t.after(async () => { await connector.close(); fs.rmSync(home, { recursive: true, force: true }); });
  const s = connector.store.createSession({ agent: 'mock', cwd: home, mode: 'normal' });
  const pending = connector.store.requestApproval({ sessionId: s.id, kind: 'shell', toolName: 'Bash', summary: 'pwd', risk: 'low' });
  const id = connector.store.approvals[0].id, url = `http://127.0.0.1:${connector.port}/approvals/${id}/trust`;
  assert.equal((await fetch(url, { method: 'POST' })).status, 401);
  assert.equal(s.mode, 'normal');
  const token = connector.store.addDevice('test').token;
  const response = await fetch(url, { method: 'POST', headers: { authorization: `Bearer ${token}` } });
  assert.equal(response.status, 200); assert.equal((await response.json()).session.mode, 'trust');
  assert.equal(await pending, 'allow');
  connector.store.configureSession(s.id, { mode: 'normal' });
  assert.equal((await fetch(url, { method: 'POST', headers: { authorization: `Bearer ${token}` } })).status, 409);
  assert.equal(s.mode, 'normal');
});
