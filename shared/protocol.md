# YzVibe 连接协议 v0.1（手机 ⇄ 桌面连接器）

三端共用。传输：HTTPS REST + WebSocket（同一 host:port，默认 9876）。鉴权：`Authorization: Bearer <token>`。

## 配对二维码
```
yzvibe://pair?host=<host>&port=9876&token=<one-time-token>&mode=tunnel|local|p2p|tailscale&name=<device-name>
```
- token 一次性、5 分钟内有效；握手成功后连接器签发长期 `deviceToken`

## REST
| 方法 | 路径 | 说明 |
|---|---|---|
| GET | /health | 公开。`{ name, version, agents, connectorId, uptime }`；`connectorId` 是电脑的稳定 ID，手机用它作 Device.id |
| POST | /pair | 公开。body `{ token, phoneName? }` → `{ deviceToken, deviceName, connectorId }`；token 一次性、10 分钟有效 |
| GET | /sessions | 会话列表 |
| POST | /sessions | `{ agent, cwd, firstMessage?, continueLast?, yolo?, model? }` → Session（201）；cwd 不存在 → 400 |
| GET | /sessions/:id | 单个会话 |
| DELETE | /sessions/:id | 结束会话 |
| GET | /sessions/:id/messages?after=<messageId> | 增量消息（after 之后的） |
| POST | /sessions/:id/messages | `{ text, attachments? }`（WS 之外的发送方式）|
| POST | /sessions/:id/stop | 中断当前轮 |
| GET | /approvals?status=pending | 审批列表（手机重启后用它恢复收件箱） |
| POST | /approvals/:id | `{ decision }`（WS 之外的审批方式）|
| GET | /files?sessionId=&path= | 目录列表 `{ path, entries:[{name,path,kind,size,modifiedAt}] }`，path 相对会话 cwd，越界 403 |
| GET | /files/preview?sessionId=&path= | 文本/图片预览（≤ 2MB） |
| GET | /files/download?sessionId=&path= | 下载 |
| POST | /uploads | 二进制 body + `Content-Type` + `X-Filename` → `{ id, url }`；发送消息时把 id 放进 attachments |
| GET | /uploads/:id | 取回上传内容 |

## WebSocket `/ws`
鉴权：`Authorization: Bearer <deviceToken>` 或 `?token=`。

### 服务端 → 客户端
```jsonc
{ "type": "session.created",    "session": { ...Session } }
{ "type": "session.status",     "sessionId": "s1", "status": "idle|running|waiting_approval|error|closed" }
{ "type": "message.delta",      "sessionId": "s1", "messageId": "m9", "role": "assistant", "text": "..." }
{ "type": "message.done",       "sessionId": "s1", "messageId": "m9" }
{ "type": "tool.call",          "sessionId": "s1", "toolId": "t1", "name": "Bash", "input": {...}, "state": "running|done|error" }
{ "type": "approval.requested", "sessionId": "s1", "approvalId": "a1", "kind": "shell|write|network|other", "summary": "rm -rf dist", "detail": "...", "risk": "low|medium|high", "expiresAt": "..." }
{ "type": "approval.resolved",  "approvalId": "a1", "decision": "allow|deny|allow_once", "by": "phone|desktop" }
```
### 客户端 → 服务端
```jsonc
{ "type": "message.send",     "sessionId": "s1", "text": "...", "attachments": ["upload-id"] }
{ "type": "session.stop",     "sessionId": "s1" }
{ "type": "session.resume",   "sessionId": "s1" }
{ "type": "approval.respond", "approvalId": "a1", "decision": "allow|deny|allow_once" }
{ "type": "ping" }
```
`allow` 会让连接器记住「本会话 + 同一工具 + 同一命令」下次自动放行；`allow_once` 只放行这一次。

## 数据模型（三端共用）
```ts
type Device  = { id, name, host, port, mode: 'tunnel'|'local'|'p2p'|'tailscale'|'relay', online: boolean, lastSeen }
type Session = { id, deviceId, agent: 'claude'|'codex'|string, cwd, title, status, createdAt, updatedAt }
type Message = { id, sessionId, role: 'user'|'assistant'|'tool'|'system', text, attachments?, toolCall?, createdAt }
type Approval= { id, sessionId, deviceId, kind: 'shell'|'write'|'network'|'other', summary, detail, risk, status: 'pending'|'allowed'|'denied'|'expired', createdAt, expiresAt? }
```

## 审批在连接器内部如何实现（Claude Code）
连接器以 `claude -p --input-format stream-json --output-format stream-json --permission-prompt-tool mcp__yzvibe__approve --mcp-config <file>` 启动 Agent。
Claude 需要权限时调用 MCP 工具 `approve`（connector/src/mcp-approve.js），它 POST 到连接器 `/internal/approval` 并等待手机决定，再返回 `{behavior:"allow"|"deny"}`。
`--yolo` 时改传 `--dangerously-skip-permissions`，不会产生审批。
