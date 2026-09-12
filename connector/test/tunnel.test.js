import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { startCloudflareTunnel, retryTunnel } from '../src/tunnel.js';

test('revoked tunnel terminates even while process remains alive; split output is supported', async () => {
  const child = new EventEmitter();
  child.stdout = new EventEmitter(); child.stderr = new EventEmitter();
  let kills = 0;
  child.kill = () => { kills++; };
  const started = startCloudflareTunnel(19876, { spawnProcess: () => child, log: () => {} });
  child.stderr.emit('data', 'https://example.trycloud');
  child.stderr.emit('data', 'flare.com\nRegistered tunnel connection\n');
  assert.equal((await started).registered, true);
  child.stderr.emit('data', 'ERR Unauthorized: Tunnel ');
  child.stderr.emit('data', 'not found\n');
  child.stderr.emit('data', 'ERR Unauthorized: Tunnel not found\n');
  assert.equal(kills, 1);
});

test('ordinary network errors do not rotate a valid tunnel URL', async () => {
  const child = new EventEmitter();
  child.stdout = new EventEmitter(); child.stderr = new EventEmitter();
  let kills = 0; child.kill = () => { kills++; };
  const started = startCloudflareTunnel(19876, { spawnProcess: () => child, log: () => {} });
  child.stderr.emit('data', 'https://example.trycloudflare.com\nRegistered tunnel connection\n');
  await started;
  child.stderr.emit('data', 'ERR connection reset by peer\n');
  assert.equal(kills, 0);
});

test('recovery survives repeated failures with capped backoff', async () => {
  let attempts = 0; const delays = [];
  const result = await retryTunnel(async () => {
    if (++attempts < 7) throw new Error('offline');
    return 'https://recovered.trycloudflare.com';
  }, { sleep: async ms => { delays.push(ms); }, log: () => {} });
  assert.equal(result, 'https://recovered.trycloudflare.com');
  assert.deepEqual(delays, [5000, 10000, 20000, 40000, 60000, 60000, 60000]);
});

test('shutdown during retry delay does not spawn another tunnel', async () => {
  let stopped = false;
  const result = await retryTunnel(() => assert.fail('must not spawn'), {
    stopped: () => stopped, sleep: async () => { stopped = true; },
  });
  assert.equal(result, null);
});
