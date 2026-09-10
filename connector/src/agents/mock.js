// 内置假 Agent：不依赖 Claude，用来演示 / 测试完整流程（流式回复 → 工具调用 → 审批 → 完成）
import { randomUUID } from 'node:crypto';

export class MockAgent {
  constructor({ session, store }) { this.session = session; this.store = store; this.running = false; this.generation = 0; }

  async send(text) {
    const { store, session } = this;
    if (this.running) return;
    this.running = true;
    const generation = ++this.generation;
    store.setStatus(session.id, 'running');
    const mid = randomUUID();
    for (const chunk of ['收到「', text.slice(0, 20), '」。', '我先看一下相关文件，', '然后执行。']) {
      await sleep(180);
      if (generation !== this.generation) return;
      store.appendDelta(session.id, mid, chunk);
    }
    store.upsertToolCall(session.id, { id: randomUUID(), name: 'Read', detail: 'src/index.ts', state: 'running' });
    await sleep(500);
    if (generation !== this.generation) return;
    const list = store.messagesOf(session.id);
    const last = [...list].reverse().find((m) => m.role === 'assistant');
    if (last?.toolCalls?.length) store.upsertToolCall(session.id, { ...last.toolCalls.at(-1), state: 'done' });
    store.finishMessage(session.id, mid);

    if (/rm|delete|删除|deploy|发布/i.test(text)) {
      const decision = await store.requestApproval({ sessionId: session.id, toolName: 'Bash', kind: 'shell', summary: 'rm -rf dist/', detail: 'rm -rf dist/\n  (mock agent 演示审批)', risk: 'high' });
      if (generation !== this.generation) return;
      const mid2 = randomUUID();
      store.appendDelta(session.id, mid2, decision === 'deny' ? '好的，已跳过删除操作。' : '已删除 dist/，任务完成。');
      store.finishMessage(session.id, mid2);
    }
    this.running = false;
    store.setStatus(session.id, 'idle');
  }

  configure() {}
  stop() { this.generation++; this.running = false; this.store.setStatus(this.session.id, 'idle'); }
  dispose() { this.generation++; this.running = false; }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
