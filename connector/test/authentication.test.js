import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { once } from 'node:events';
import { WebSocket } from 'ws';
import { Store } from '../src/store.js';
import { createConnector } from '../src/server.js';

async function fixture(t) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-auth-'));
  const connector = await createConnector({ home, port: 0, defaultAgent: 'mock', importTerminal: false, log: () => {} });
  await connector.listen();
  t.after(async () => { await connector.close(); fs.rmSync(home, { recursive: true, force: true }); });
  const phone = connector.store.addDevice('phone');
  return { home, connector, phone, base: `http://127.0.0.1:${connector.port}` };
}

async function rejectsSocket(url, token) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url, { handshakeTimeout: 2000, headers: token ? { authorization: `Bearer ${token}` } : {} });
    ws.on('error', () => {});
    ws.on('open', () => { ws.terminate(); reject(new Error('Unauthenticated socket opened')); });
    ws.on('unexpected-response', (_request, response) => { response.resume(); ws.terminate(); resolve(response.statusCode); });
    ws.on('close', () => resolve(0));
  });
}

test('all business HTTP routes reject missing and invalid device tokens while health stays public', async t => {
  const { connector, phone, base } = await fixture(t);
  assert.equal((await fetch(base + '/health')).status, 200);
  const routes = [['GET', '/sessions'], ['GET', '/diagnostics'], ['GET', '/rules'], ['GET', '/sessions/missing/runs'], ['GET', '/uploads/missing'], ['POST', '/sessions'], ['DELETE', '/rules/missing']];
  for (const token of [null, 'invalid-fixture-token']) {
    for (const [method, route] of routes) {
      const response = await fetch(base + route, { method, headers: token ? { authorization: `Bearer ${token}` } : {} });
      assert.equal(response.status, 401, `${method} ${route}`);
      await response.text();
    }
  }
  for (const host of ['127.0.0.1', 'localhost']) {
    const response = await fetch(`http://${host}:${connector.port}/rules`, { headers: { authorization: `Bearer ${phone.token}` } });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), []);
  }
});

test('device tokens are independent, durable and absent from device listing', async t => {
  const { connector, phone, home } = await fixture(t);
  const second = connector.store.addDevice('second phone');
  assert.match(phone.token, /^[a-f0-9]{64}$/);
  assert.notEqual(phone.token, second.token);
  assert.equal(new Store(home).deviceByToken(phone.token)?.id, phone.id);
  assert.ok(connector.store.listDevices().every(device => !('token' in device)));
});

test('WebSocket authenticates Bearer header and revocation disconnects only the revoked phone', async t => {
  const { connector, phone, base } = await fixture(t);
  const url = base.replace('http:', 'ws:') + '/ws';
  assert.equal(await rejectsSocket(url, null), 401);
  assert.equal(await rejectsSocket(url, 'invalid-fixture-token'), 401);
  const other = connector.store.addDevice('other phone');
  const ws = new WebSocket(url, { headers: { authorization: `Bearer ${phone.token}` } });
  const otherWS = new WebSocket(url, { headers: { authorization: `Bearer ${other.token}` } });
  t.after(() => { ws.terminate(); otherWS.terminate(); });
  await Promise.all([once(ws, 'open'), once(otherWS, 'open')]);
  const closed = once(ws, 'close');
  connector.store.removeDevice(phone.id);
  await closed;
  assert.equal(otherWS.readyState, WebSocket.OPEN);
  assert.equal((await fetch(base + '/rules', { headers: { authorization: `Bearer ${phone.token}` } })).status, 401);
  assert.equal(await rejectsSocket(url, phone.token), 401);
  assert.equal((await fetch(base + '/rules', { headers: { authorization: `Bearer ${other.token}` } })).status, 200);
});
