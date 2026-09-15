import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Store } from '../src/store.js';
import { OmpAgent } from '../src/agents/omp.js';
import { ompSubagent } from '../src/agents/omp-progress.js';
import { parseOmpTranscript } from '../src/agents/omp-transcripts.js';

function setup(t) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'omp-progress-'));
  const store = new Store(home), session = store.createSession({ agent: 'omp', cwd: home });
  const agent = new OmpAgent({ session, store });
  agent.rpc = { request: async () => ({}), close() {} };
  agent.active = { prefix: 'run', messages: new Set(), done: new Set(), usage: [], started: Date.now() };
  store.setStatus(session.id, 'running');
  const events = []; store.on('event', event => events.push(structuredClone(event)));
  t.after(() => { agent.dispose(); fs.rmSync(home, { recursive: true, force: true }); });
  return { agent, store, session, events, home };
}
test('thinking and final text reach live clients and survive reconnect without signatures', t => {
  const { agent, store, session, events, home } = setup(t);
  agent.event({ type: 'message_start', message: { role: 'assistant' } });
  agent.event({ type: 'message_update', assistantMessageEvent: { type: 'thinking_delta', delta: '核对项目' } });
  agent.flushThinking();
  assert.equal(events.at(-1).message.thinking, '核对项目');
  agent.event({ type: 'message_end', message: { role: 'assistant', content: [
    { type: 'thinking', thinking: '核对项目依赖', thinkingSignature: 'opaque-signature' }, { type: 'text', text: '正在检查依赖' },
  ] } });
  const full = events.findLast(e => e.type === 'message.updated').message;
  assert.equal(full.text, '正在检查依赖'); assert.equal(full.streaming, false);
  assert.equal(full.thinking, '核对项目依赖'); assert.doesNotMatch(JSON.stringify(full), /opaque-signature/);
  assert.equal(new Store(home).messagesOf(session.id)[0].thinking, full.thinking);
  assert.equal(store.messagesOf(session.id).length, 1);
});
test('detached task stays running after tool returns; late child progress stays on original tool', async t => {
  const { agent, store, session, events } = setup(t);
  agent.event({ type: 'message_start', message: { role: 'assistant' } });
  agent.event({ type: 'tool_execution_start', toolCallId: 'task-1', toolName: 'task', args: { task: 'Audit' } });
  const owner = store.messagesOf(session.id)[0].id;
  agent.event({ type: 'subagent_lifecycle', payload: { id: 'BuildScout', agent: 'scout', status: 'started', parentToolCallId: 'task-1', index: 0 } });
  agent.event({ type: 'tool_execution_end', toolCallId: 'task-1', toolName: 'task', result: { content: [], details: { async: { state: 'running' } } } });
  assert.equal(store.messagesOf(session.id)[0].toolCalls[0].state, 'running');
  agent.event({ type: 'message_start', message: { role: 'assistant' } });
  agent.event({ type: 'message_update', assistantMessageEvent: { type: 'text_delta', delta: '等待检查' } });
  agent.event({ type: 'subagent_progress', payload: { parentToolCallId: 'task-1', progress: { id: 'BuildScout', task: 'Audit build', status: 'running', currentTool: 'read', durationMs: 12_000, toolCount: 8 } } });
  agent.event({ type: 'subagent_lifecycle', payload: { id: 'BuildScout', status: 'completed', parentToolCallId: 'task-1' } });
  const last = events.findLast(e => e.type === 'tool.call');
  assert.equal(last.messageId, owner); assert.equal(last.state, 'done');
  assert.equal(last.subagents[0].toolCount, 8); assert.equal(last.subagents[0].task, 'Audit build');
  agent.event({ type: 'agent_end', isTerminal: false }); assert.equal(session.status, 'running');
  await agent.finish('completed'); assert.equal(session.status, 'idle');
});
test('task details fallback preserves child progress and final results', t => {
  const { agent, store, session } = setup(t);
  const event = (type, details) => agent.event({ type, toolCallId: 't', toolName: 'task', partialResult: { content: [], details } });
  event('tool_execution_update', { progress: [{ id: 'Scout', status: 'running', task: '检查构建', toolCount: 3 }] });
  agent.flushProgress();
  event('tool_execution_update', { async: { state: 'completed' }, results: [{ id: 'Scout', exitCode: 0, durationMs: 10_000 }] });
  agent.flushProgress();
  const call = store.messagesOf(session.id)[0].toolCalls[0];
  assert.equal(call.state, 'done'); assert.equal(call.subagents[0].status, 'completed');
  assert.equal(call.subagents[0].task, '检查构建'); assert.equal(call.subagents[0].toolCount, 3);
});
test('disconnect ends running indicators without changing completed children', t => {
  const { agent, store, session } = setup(t);
  for (const [id, status] of [['A', 'running'], ['B', 'completed']]) {
    agent.event({ type: 'subagent_progress', payload: { parentToolCallId: 't', progress: { id, status } } });
  }
  agent.fail(new Error('Disconnected'));
  const call = store.messagesOf(session.id)[0].toolCalls[0];
  assert.equal(call.state, 'error'); assert.deepEqual(call.subagents.map(p => p.status), ['unknown', 'completed']);
  assert.equal(session.status, 'error');
});
test('explicit background failure overrides cached running progress', t => {
  const { agent, store, session } = setup(t);
  agent.event({ type: 'subagent_lifecycle', payload: { id: 'A', status: 'started', parentToolCallId: 't' } });
  agent.event({ type: 'tool_execution_update', toolCallId: 't', toolName: 'task', partialResult: { content: [], details: { async: { state: 'failed' } } } });
  agent.flushProgress();
  const call = store.messagesOf(session.id)[0].toolCalls[0];
  assert.equal(call.state, 'error'); assert.equal(call.subagents[0].status, 'unknown');
  agent.event({ type: 'subagent_lifecycle', payload: { id: 'A', status: 'completed', parentToolCallId: 't' } });
  assert.equal(store.messagesOf(session.id)[0].toolCalls[0].state, 'error');
});
test('retry status and elapsed time are bounded projections', () => {
  const start = ompSubagent({ id: 'A', status: 'running', durationMs: 3000, retryState: { attempt: 2, maxAttempts: 4, errorMessage: '429' } }, {}, 10_000);
  assert.match(start.detail, /等待重试 2\/4/);
  const end = ompSubagent({ id: 'A', status: 'completed' }, start, 12_000);
  assert.equal(end.durationMs, 5000);
});
test('bursts of child updates are coalesced and terminal lifecycle flushes the latest progress', t => {
  const { agent, events } = setup(t);
  agent.event({ type: 'subagent_lifecycle', payload: { id: 'A', status: 'started', parentToolCallId: 't' } });
  for (let i = 1; i <= 100; i++) agent.event({ type: 'subagent_progress', payload: { parentToolCallId: 't', progress: { id: 'A', status: 'running', toolCount: i } } });
  assert.equal(events.filter(e => e.type === 'tool.call').length, 1);
  agent.event({ type: 'subagent_lifecycle', payload: { id: 'A', status: 'completed', parentToolCallId: 't' } });
  const updates = events.filter(e => e.type === 'tool.call');
  assert.equal(updates.length, 3); assert.equal(updates.at(-1).subagents[0].toolCount, 100);
  assert.equal(updates.at(-1).subagents[0].status, 'completed');
});
test('native history preserves thinking and child results, marks unfinished snapshots unknown', t => {
  const { home, session } = setup(t); const file = path.join(home, 'history.jsonl');
  fs.writeFileSync(file, [
    { id: 'a', parentId: null, type: 'message', message: { role: 'assistant', content: [{ type: 'thinking', thinking: '分析依赖' }, { type: 'toolCall', id: 't', name: 'task', arguments: {} }] } },
    { id: 'b', parentId: 'a', type: 'message', message: { role: 'toolResult', toolCallId: 't', content: [], details: { progress: [{ id: 'A', status: 'running' }], results: [{ id: 'B', exitCode: 0 }] } } },
  ].map(JSON.stringify).join('\n'));
  const [message] = parseOmpTranscript(file, session.id);
  assert.equal(message.thinking, '分析依赖');
  assert.deepEqual(message.toolCalls[0].subagents.map(p => p.status), ['unknown', 'completed']);
});
