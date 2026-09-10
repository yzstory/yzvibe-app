# YzVibe 连接协议 v0.1（手机 ⇄ 桌面连接器）

三端共用。传输：HTTPS REST + WebSocket（同一 host:port，默认 19876；被占用时连接器自动后移，二维码携带实际端口）。鉴权：`Authorization: Bearer <token>`。

## 配对二维码
```
yzvibe://pair?host=<host>&port=19876&token=<one-time-token>&mode=tunnel|local|p2p|tailscale&name=<device-name>
```
- token 一次性、5 分钟内有效；握手成功后连接器签发长期 `deviceToken`

## REST
| 方法 | 路径 | 说明 |
|---|---|---|
| GET | /health | 公开。`{ name, version, agents, connectorId, uptime }`；`connectorId` 是电脑的稳定 ID，手机用它作 Device.id |
| POST | /pair | 公开。body `{ token, phoneName? }` → `{ deviceToken, deviceName, connectorId }`；token 一次性、10 分钟有效 |
| GET | /agents | 各 Agent 的能力表：`{ claude: { modes, efforts, models, customModel }, codex: {...} }`，见下文「会话选项」 |
| GET | /fs/dirs?path= | 目录浏览（选工作目录用）：`{ path, parent, home, entries:[{name,path}] }`，只列目录、跳过隐藏项；path 缺省为主目录 |
| POST | /fs/mkdir | `{ parent, name }` → `{ path }`（201）；名字含路径分隔符或以 . 开头 → 400 |
| GET | /quota?agent=claude\|codex | 账号剩余额度，见下文「用量与额度」 |
| GET | /sessions | 会话列表 |
| POST | /sessions | `{ agent, cwd, firstMessage?, continueLast?, mode?, model?, effort? }` → Session（201）；cwd 不存在 → 400。旧字段 `yolo:true` 等价 `mode:'trust'` |
| GET | /sessions/:id | 单个会话 |
| PATCH | /sessions/:id | `{ mode?, model?, effort? }` 改会话选项 → Session；`model`/`effort` 传 `null` 或空串恢复默认；广播 `session.updated` |
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
{ "type": "session.updated",    "session": { ...Session } }   // 标题等元数据变化
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
{ "type": "session.configure","sessionId": "s1", "mode": "plan", "model": "opus", "effort": "high" }   // 同 PATCH /sessions/:id
{ "type": "approval.respond", "approvalId": "a1", "decision": "allow|deny|allow_once" }
{ "type": "ping" }
```
`allow` 会让连接器记住「本会话 + 同一工具 + 同一命令」下次自动放行；`allow_once` 只放行这一次。

## 数据模型（三端共用）
```ts
type Device  = { id, name, host, port, mode: 'tunnel'|'local'|'p2p'|'tailscale'|'relay', online: boolean, lastSeen }
type Session = { id, deviceId, agent: 'claude'|'codex'|string, cwd, title, status, createdAt, updatedAt, mode: 'plan'|'normal'|'trust', model: string|null, effort: string|null, usage: SessionUsage|null }
type SessionUsage = { model, turn: TurnUsage, total: { input, cacheWrite, cacheRead, output, thinking, costUSD|null, turns }, updatedAt }
type TurnUsage = { model, input, cacheWrite, cacheRead, output, thinking, contextTokens, contextWindow, costUSD|null, durationMs|null }
type Message = { id, sessionId, role: 'user'|'assistant'|'tool'|'system', text, attachments?, toolCall?, createdAt }
type Approval= { id, sessionId, deviceId, kind: 'shell'|'write'|'network'|'other', summary, detail, risk, status: 'pending'|'allowed'|'denied'|'expired', createdAt, expiresAt? }
```

## 审批在连接器内部如何实现（Claude Code）
连接器以 `claude -p --input-format stream-json --output-format stream-json --permission-prompt-tool mcp__yzvibe__approve --mcp-config <file>` 启动 Agent。
Claude 需要权限时调用 MCP 工具 `approve`（connector/src/mcp-approve.js），它 POST 到连接器 `/internal/approval` 并等待手机决定，再返回 `{behavior:"allow"|"deny"}`。
`--yolo` 时改传 `--dangerously-skip-permissions`，不会产生审批。

## 会话选项：模式 / 模型 / 思考强度

三端统一叫 **Plan / Normal / Trust**，连接器按 Agent 翻译（`connector/src/agents/options.js`）：

| 选项 | Claude Code | Codex CLI |
|---|---|---|
| Plan | `--permission-mode plan`（仍带 `--permission-prompt-tool`；`ExitPlanMode` 会作为一条低风险审批发到手机，批准后会话自动切回 Normal） | `-c sandbox_mode="read-only"` + 提示词前缀「只规划不改文件」（Codex 非交互没有原生 plan） |
| Normal | `--permission-prompt-tool mcp__yzvibe__approve`（敏感操作发手机审批） | `-c sandbox_mode="workspace-write" -c approval_policy="never"`：沙箱内自动执行，沙箱外操作被拒绝，**不会产生审批** |
| Trust | `--dangerously-skip-permissions` | `--dangerously-bypass-approvals-and-sandbox` |
| model | `--model <alias 或完整 id>`；预置 fable / opus / sonnet / haiku，支持自定义 | `-m <slug>`；列表来自 `codex debug models`（10 分钟缓存），支持自定义 |
| effort | `--effort low|medium|high|xhigh|max` | `-c model_reasoning_effort="…"`；档位随模型（目录里带 `efforts`） |

生效时机：Codex 每轮是独立进程，下一轮即生效；Claude 是常驻进程，连接器在会话空闲时于下一轮用 `--resume <session>` 重启进程带上新参数（运行中时等本轮结束）。
`GET /agents` 返回的每个 Agent：`modes[plan|normal|trust] = { flag, description }`、`efforts: string[]`、`models: [{ id, label, description?, efforts?, defaultEffort? }]`、`customModel: boolean`。手机端在连接器不可达或版本较旧时使用内置回退表。

## 用量与额度

- **每轮用量**：一轮结束时连接器把 Agent 的原始统计归一成 `Session.usage`（`connector/src/agents/usage.js`）并广播 `session.updated`。
  Claude 取 `result.usage` / `modelUsage`（含 `contextWindow`、目录价 `costUSD`），上下文大小取最后一条 assistant 消息的 `input + cache_creation + cache_read`；
  Codex 取 `turn.completed.usage`（`input_tokens` 已含 `cached_input_tokens`），上下文窗口来自 `codex debug models` 的 `context_window`，没有费用估算。
  `total` 由连接器自己累加，重启进程（切模型等）不会清零。
- **账号额度** `GET /quota?agent=claude`：连接器用本机 Claude Code 的 OAuth token（macOS 钥匙串 `Claude Code-credentials`，或 `~/.claude/.credentials.json`）调
  `https://api.anthropic.com/api/oauth/usage`，归一成 `{ agent, source: 'oauth'|'rate_limit_event'|'none', fetchedAt, limits: [{ id, label, percent, resetsAt }], extraUsage, error?, warning?, unavailable? }`。
  `limits` 里 `session` = 5 小时窗口，`weekly_all` = 本周所有模型，`weekly_fable` 等 = 该模型的本周额度（来自接口 `limits[].kind = weekly_scoped` 的 `scope.model.display_name`）。
  接口失败时退回最近一次流式输出里的 `rate_limit_event`（`unifiedWindows.five_hour / seven_day / seven_day_overage_included(Fable)`），并带 `warning`。结果缓存 60 秒，`?force=1` 强刷。
  Codex 返回 `unavailable`：非交互模式没有额度接口。
- **手机端图片**：上传前长边缩到 1568px 并转 JPEG（`ios/…/ImagePrep.swift`），与 API 的缩放阈值一致，避免原图超过 5MB 被拒绝。
