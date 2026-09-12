import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { readCodexContext } from '../src/transcripts.js';
import { codexTurnUsage } from '../src/agents/usage.js';
import { Store } from '../src/store.js';

test('上下文取指定线程最后一次调用，不使用累计、缓存加算或默认窗口', (t) => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'yz-context-'));
  t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  const dir = path.join(home, 'sessions/2026/09/12');
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, 'rollout-2026-09-12-thread-one.jsonl');
  const event = (input, output, window) => JSON.stringify({ type: 'event_msg', payload: { type: 'token_count', info: {
    total_token_usage: { input_tokens: 589549 },
    last_token_usage: { input_tokens: input, output_tokens: output, cached_input_tokens: 65000 },
    model_context_window: window,
  } } });
  fs.writeFileSync(file, event(90000, 100, 272000) + '\n' + event(69950, 86, 258400) + '\n');
  assert.deepEqual(readCodexContext('thread-one', { codexHome: home }), { contextTokens: 70036, contextWindow: 258400 });
  assert.equal(readCodexContext('other-thread', { codexHome: home }), null);
  // 文件追加后刷新缓存；上下文压缩后可以变小。
  fs.appendFileSync(file, event(12000, 50, 258400) + '\n');
  assert.equal(readCodexContext('thread-one', { codexHome: home }).contextTokens, 12050);
  fs.appendFileSync(file, event(15000, 60, null) + '\n');
  assert.equal(readCodexContext('thread-one', { codexHome: home }), null);
});

test('整轮累计仍保留，但不能冒充上下文；旧版缓存的错误值不再对外返回', (t) => {
  const turn = codexTurnUsage({ input_tokens: 589549, cached_input_tokens: 573440, output_tokens: 2636 }, 'gpt-6-astra', 272000);
  assert.equal(turn.input + turn.cacheRead, 589549);
  assert.equal(turn.contextTokens, null);
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'yz-context-store-'));
  t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  const store = new Store(home);
  const session = store.createSession({ agent: 'codex', cwd: home, title: 'test' });
  session.usage = { turn: { ...turn, contextTokens: 589549, contextWindow: 272000 }, total: { input: 107544 } };
  assert.equal(store.publicSession(session).usage.turn.contextTokens, null);
  assert.equal(store.publicSession(session).usage.total.input, 107544);
});
