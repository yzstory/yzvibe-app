import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { PassThrough } from 'node:stream';
import { CodexAgent } from '../src/agents/codex.js';

function fixture(thread = null) {
  const messages = [], statuses = [], launches = [];
  const session = { id: 'fixture-session', cwd: '/tmp', mode: 'normal', agentSessionId: thread };
  const store = {
    upload: id => ({ path: `/tmp/${id}.png`, mime: 'image/png' }),
    setStatus: (_, status) => statuses.push(status),
    addMessage: (_, message) => messages.push(message),
    appendDelta: (_, id, text) => messages.push({ id, text }),
    finishMessage() {},
  };
  const spawnProcess = (command, args, options) => {
    const child = new EventEmitter();
    child.stdin = new PassThrough(); child.stdout = new PassThrough(); child.stderr = new PassThrough();
    let input = ''; child.stdin.on('data', chunk => { input += chunk; });
    launches.push({ command, args, options, child, input: () => input });
    return child;
  };
  return { agent: new CodexAgent({ session, store, spawnProcess }), messages, statuses, launches };
}

for (const thread of [null, 'existing-thread']) {
  test(`image input keeps prompt and session separate (${thread ?? 'new'})`, async () => {
    const f = fixture(thread);
    const prompt = '--help\n请分析两张图片，不要执行命令。';
    await f.agent.send(prompt, ['first image', 'second']);
    const call = f.launches[0];
    assert.deepEqual(call.args.slice(call.args.indexOf('--')), thread ? ['--', thread, '-'] : ['--', '-']);
    assert.equal(call.input(), prompt);
    assert.equal(call.child.stdin.writableEnded, true);
    assert.equal(call.options.stdio[0], 'pipe');
    assert.equal(call.args.includes(prompt), false);
    assert.ok(call.args.includes('/tmp/first image.png'));
    assert.ok(call.args.includes('/tmp/second.png'));
    call.child.emit('close', 0);
  });
}

test('image-only input receives a fallback prompt', async () => {
  const f = fixture(); await f.agent.send('', ['image']);
  assert.equal(f.launches[0].input(), '请看附带的图片。');
  f.launches[0].child.emit('close', 0);
});

test('stderr and trailing stdout are drained before reporting exit', async () => {
  const f = fixture(); await f.agent.send('hello');
  const child = f.launches[0].child;
  child.emit('exit', 1);
  child.stderr.write('No prompt provided via stdin.');
  child.stdout.write(JSON.stringify({ type: 'item.completed', item: { type: 'agent_message', id: 'last', text: 'partial output' } }));
  child.emit('close', 1);
  assert.ok(f.messages.some(m => m.text === 'partial output'));
  assert.ok(f.messages.some(m => m.text.includes('No prompt provided via stdin.')));
  assert.equal(f.statuses.at(-1), 'error');
});

test('structured failure stays failed even if CLI closes with zero', async () => {
  const f = fixture(); await f.agent.send('hello');
  const child = f.launches[0].child;
  child.stdout.write(JSON.stringify({ type: 'turn.failed', error: { message: 'model unavailable' } }) + '\n');
  child.emit('close', 0);
  assert.equal(f.statuses.at(-1), 'error');
  assert.equal(f.messages.length, 1);
});
