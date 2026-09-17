import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { normalizeCodexQuota, agentQuota } from '../src/quota.js';
import { codexRateLimits } from '../src/transcripts.js';

const general = { limitId: 'codex', primary: { usedPercent: 54, windowDurationMins: 10080 } };
const spark = { limitId: 'codex_bengalfox', primary: { usedPercent: 0, windowDurationMins: 300 } };

test('Codex uses the general bucket and does not invent missing windows or percentages', () => {
  assert.deepEqual(normalizeCodexQuota({ rateLimits: spark, rateLimitsByLimitId: { codex: general } }).limits.map(x => [x.id, x.percent]), [['weekly_all', 54]]);
  assert.deepEqual(normalizeCodexQuota({ rateLimits: spark }).limits, []);
  for (const usedPercent of [null, undefined, NaN, -1, 101]) {
    assert.deepEqual(normalizeCodexQuota({ rateLimits: { ...general, primary: { usedPercent } } }).limits, []);
  }
  assert.equal(normalizeCodexQuota({ rateLimits: { ...general, primary: { usedPercent: 0, windowDurationMins: 300 } } }).limits[0].percent, 0);
});

test('Codex queries live account quota, closes RPC, and labels fallback honestly', async () => {
  for (const failed of [false, true]) {
    const calls = [];
    let closed = false;
    const quota = await agentQuota('codex', {
      codexRPCFactory: () => ({
        on() {},
        notify(method) { calls.push(method); },
        async request(method) {
          calls.push(method);
          if (method === 'initialize') return {};
          if (failed) throw new Error('offline');
          return { rateLimits: general };
        },
        close() { closed = true; },
      }),
      readCodexRateLimits: () => ({ at: 1000, limits: [{ id: 'weekly_all', percent: 53, window: 'primary' }] }),
    });
    assert.equal(closed, true);
    assert.deepEqual(calls, ['initialize', 'initialized', 'account/rateLimits/read']);
    assert.equal(quota.source, failed ? 'codex_session' : 'codex_app_server');
    assert.equal(quota.limits[0].percent, failed ? 53 : 54);
    if (failed) {
      assert.ok(quota.warning);
      assert.equal(quota.fetchedAt, new Date(1000).toISOString());
    }
  }
});

test('Historical quota ignores Spark and uses event time instead of file mtime', () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'yz-quota-'));
  try {
    const day = path.join(home, 'sessions', '2026', '09', '17');
    fs.mkdirSync(day, { recursive: true });
    const event = (timestamp, id, percent) => JSON.stringify({
      timestamp, type: 'event_msg', payload: { type: 'token_count',
        rate_limits: { limit_id: id, primary: { used_percent: percent, window_minutes: 10080 } } },
    });
    fs.writeFileSync(path.join(day, 'rollout-a.jsonl'), [
      event('2026-09-17T14:07:40Z', 'codex', 53),
      event('2026-09-17T14:08:00Z', 'codex_bengalfox', 0),
    ].join('\n'));
    fs.writeFileSync(path.join(day, 'rollout-b.jsonl'), event('2026-09-17T13:00:00Z', 'codex', 20) + '\n'.padEnd(250, ' '));
    const quota = codexRateLimits({ codexHome: home });
    assert.equal(quota.limits[0].percent, 53);
    assert.equal(quota.at, Date.parse('2026-09-17T14:07:40Z'));
  } finally { fs.rmSync(home, { recursive: true, force: true }); }
});
