#!/usr/bin/env node
// 最小 MCP stdio 服务器：Claude Code 的 --permission-prompt-tool 调用 approve，
// 我们转发到连接器内部接口等待手机决定，再按约定返回 {behavior:"allow"|"deny"}。
import { createInterface } from 'node:readline';

const INTERNAL = process.env.YZVIBE_INTERNAL;
const SECRET = process.env.YZVIBE_SECRET;
const SESSION = process.env.YZVIBE_SESSION;

const rl = createInterface({ input: process.stdin });
const reply = (id, result) => process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id, result }) + '\n');
const replyError = (id, code, message) => process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id, error: { code, message } }) + '\n');

rl.on('line', async (line) => {
  let msg; try { msg = JSON.parse(line); } catch { return; }
  const { id, method, params } = msg;
  if (method === 'initialize') {
    return reply(id, { protocolVersion: params?.protocolVersion ?? '2024-11-05', capabilities: { tools: {} }, serverInfo: { name: 'yzvibe', version: '0.1.0' } });
  }
  if (method === 'ping') return reply(id, {});
  if (method === 'tools/list') {
    return reply(id, { tools: [{
      name: 'approve',
      description: '把工具权限请求发送到手机上的 YzVibe App，等待用户批准或拒绝。',
      inputSchema: { type: 'object', properties: { tool_name: { type: 'string' }, input: { type: 'object' }, tool_use_id: { type: 'string' } }, required: ['tool_name', 'input'] },
    }] });
  }
  if (method === 'tools/call') {
    if (params?.name !== 'approve') return replyError(id, -32601, 'unknown tool');
    const { tool_name, input, tool_use_id } = params.arguments ?? {};
    let decision = 'deny', message = '手机端未响应';
    try {
      const res = await fetch(INTERNAL, { method: 'POST', headers: { 'content-type': 'application/json', 'x-yzvibe-secret': SECRET },
        body: JSON.stringify({ sessionId: SESSION, toolName: tool_name, input, toolUseId: tool_use_id }) });
      const data = await res.json();
      decision = data.decision; message = data.message ?? '';
    } catch (e) { message = `连接器不可达：${e.message}`; }
    const result = decision === 'deny' ? { behavior: 'deny', message: message || '用户在手机上拒绝了此操作' } : { behavior: 'allow', updatedInput: input };
    return reply(id, { content: [{ type: 'text', text: JSON.stringify(result) }] });
  }
  if (id !== undefined) replyError(id, -32601, `unknown method ${method}`);
});
