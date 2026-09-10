// Claude stream-json 事件流 → 消息 / 工具卡 / 用量。用录制的事件夹具跑，不起真实 claude 进程：
// CLI 升级导致事件结构变化时，这些用例会先失败，而不是等到手机上看到空白气泡才发现。
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Store } from '../src/store.js';
import { ClaudeStreamTranslator, toolResultText, classifyPermission } from '../src/agents/claude.js';
import { lineDiff, diffText, diffFromToolInput } from '../src/diff.js';

const newStore = () => new Store(fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-stream-')));

/** 一轮真实对话的事件序列：文本流式 → Bash 工具 → 结果 → Edit 工具 → 结果 → result。 */
const TURN = [
  { type: 'system', subtype: 'init', session_id: 'agent-abc', model: 'claude-fable-5-1' },
  { type: 'stream_event', event: { type: 'content_block_delta', delta: { type: 'text_delta', text: '我先跑一下' } } },
  { type: 'stream_event', event: { type: 'content_block_delta', delta: { type: 'text_delta', text: '测试。' } } },
  { type: 'assistant', message: {
      usage: { input_tokens: 120, cache_creation_input_tokens: 40, cache_read_input_tokens: 3000 },
      content: [{ type: 'text', text: '我先跑一下测试。' }, { type: 'tool_use', id: 'toolu_1', name: 'Bash', input: { command: 'npm test' } }] } },
  { type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: 'toolu_1', content: [{ type: 'text', text: 'PASS  12 passed' }] }] } },
  { type: 'assistant', message: { content: [{ type: 'tool_use', id: 'toolu_2', name: 'Edit',
      input: { file_path: '/proj/a.ts', old_string: 'const a = 1', new_string: 'const a = 2' } }] } },
  { type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: 'toolu_2', content: 'The file has been updated.' }] } },
  { type: 'result', subtype: 'success', session_id: 'agent-abc',
    usage: { input_tokens: 120, output_tokens: 300, cache_creation_input_tokens: 40, cache_read_input_tokens: 3000 },
    modelUsage: { 'claude-fable-5-1': { inputTokens: 120, cacheReadInputTokens: 3000, contextWindow: 200_000 } },
    total_cost_usd: 0.021, duration_ms: 4200 },
];

test('Claude 事件流：文本 / 工具输出 / Edit diff / 用量 / 结束回调', () => {
  const store = newStore();
  const s = store.createSession({ agent: 'claude', cwd: os.tmpdir(), title: '测试' });
  let turnEnds = 0;
  const t = new ClaudeStreamTranslator({ store, session: s, onTurnEnd: () => { turnEnds += 1; } });
  const toolEvents = [];
  store.on('event', (e) => { if (e.type === 'tool.call') toolEvents.push(e); });
  for (const ev of TURN) t.handle(ev);

  const msgs = store.messagesOf(s.id);
  assert.equal(msgs[0].role, 'assistant');
  assert.equal(msgs[0].text, '我先跑一下测试。');
  assert.equal(msgs[0].streaming, false);

  const all = msgs.flatMap((m) => m.toolCalls);
  const bash = all.find((x) => x.id === 'toolu_1');
  assert.equal(bash.name, 'Bash');
  assert.equal(bash.detail, 'npm test');
  assert.equal(bash.state, 'done');
  assert.equal(bash.output, 'PASS  12 passed');       // 之前只显示「完成」，看不到结果
  assert.equal(bash.outputKind, 'text');

  const edit = all.find((x) => x.id === 'toolu_2');
  assert.equal(edit.state, 'done');
  assert.equal(edit.outputKind, 'diff');
  assert.match(edit.output, /-const a = 1/);
  assert.match(edit.output, /\+const a = 2/);
  assert.doesNotMatch(edit.output, /has been updated/);   // diff 不该被成功提示覆盖
  assert.equal(msgs.find((m) => m.toolCalls.some((x) => x.id === 'toolu_2')).id !== msgs[0].id, true, '第二轮工具卡应在新气泡里');

  assert.equal(s.agentSessionId, 'agent-abc');
  assert.equal(s.status, 'idle');
  assert.equal(s.usage.turn.contextTokens, 3160);          // input + cacheWrite + cacheRead
  assert.equal(s.usage.turn.contextWindow, 200_000);
  assert.equal(s.usage.total.turns, 1);
  assert.equal(Math.round(s.usage.turn.costUSD * 1000), 21);
  assert.equal(turnEnds, 1);
  assert.equal(toolEvents.at(-1).messageId, msgs.at(-1).id);
});

test('Claude 事件流：工具失败与超长输出截断', () => {
  const store = newStore();
  const s = store.createSession({ agent: 'claude', cwd: os.tmpdir(), title: 'x' });
  const t = new ClaudeStreamTranslator({ store, session: s });
  t.handle({ type: 'assistant', message: { content: [{ type: 'tool_use', id: 'e1', name: 'Bash', input: { command: 'make' } }] } });
  t.handle({ type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: 'e1', is_error: true, content: 'error: ' + 'x'.repeat(9000) }] } });
  const call = store.messagesOf(s.id).flatMap((m) => m.toolCalls).find((x) => x.id === 'e1');
  assert.equal(call.state, 'error');
  assert.equal(call.truncated, true);
  assert.ok(call.output.length < 5000);
  assert.match(call.output, /中间省略/);
});

test('Claude 事件流：出错的 result 写系统消息并把会话标成 error', () => {
  const store = newStore();
  const s = store.createSession({ agent: 'claude', cwd: os.tmpdir(), title: 'x' });
  new ClaudeStreamTranslator({ store, session: s }).handle({ type: 'result', subtype: 'error_during_execution', is_error: true, result: '额度用完了' });
  assert.equal(s.status, 'error');
  assert.match(store.messagesOf(s.id).at(-1).text, /额度用完了/);
});

test('tool_result 文本提取', () => {
  assert.equal(toolResultText('  hi  '), 'hi');
  assert.equal(toolResultText([{ type: 'text', text: 'a' }, { type: 'image' }, { type: 'text', text: 'b' }]), 'a\n[图片]\nb');
  assert.equal(toolResultText(undefined), '');
});

test('行 diff 与工具输入 diff', () => {
  assert.deepEqual(lineDiff('a\nb', 'a\nc'), [{ type: ' ', text: 'a' }, { type: '-', text: 'b' }, { type: '+', text: 'c' }]);
  assert.equal(diffText('same', 'same'), '');
  assert.match(diffFromToolInput('Write', { content: 'hello' }), /\+hello/);
  assert.match(diffFromToolInput('MultiEdit', { edits: [{ old_string: 'a', new_string: 'b' }] }), /第 1 处/);
  assert.equal(diffFromToolInput('Bash', { command: 'ls' }), null);
});

test('审批分类：写文件请求里带上 diff，方便在手机上直接看改了什么', () => {
  const c = classifyPermission('Edit', { file_path: '/p/a.ts', old_string: 'x = 1', new_string: 'x = 2' });
  assert.equal(c.kind, 'write');
  assert.match(c.detail, /-x = 1/);
  assert.match(c.detail, /\+x = 2/);
  assert.equal(classifyPermission('Bash', { command: 'sudo rm -rf /' }).risk, 'high');
});
