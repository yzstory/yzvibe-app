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
| GET | /sync | 一次拿全：`{ serverTime, sessions, approvals, agents, rules, push }`。App 回到前台补数据用，省往返 |
| GET | /rules?sessionId= | 审批规则列表（带中文 `description`） |
| POST | /rules | 手动新增一条规则 |
| DELETE | /rules/:id | 撤销一条规则 |
| POST | /devices/push | `{ token, environment: sandbox\|production, bundleId }` 注册 APNs token |
| POST | /devices/live-activity | `{ sessionId, token, environment }` 注册锁屏 / 灵动岛活动的推送 token |
| GET | /sessions/:id/diff?scope= | 工作目录改动：`{ repo, branch, head, files:[{path,status,added,removed,diff,untracked}], totals, truncated }`；`scope=session` 跟会话基线 commit 比 |
| GET | /sessions/:id/commands | 可用命令与 skill：`{ app, agentCommands, skills, prompts, note?, reported }` |
| DELETE | /sessions/:id/queue/:itemId | 撤掉一条还没发出去的排队消息 |
| DELETE | /devices/push | 注销本机推送 |
| GET | /fs/dirs?path= | 目录浏览（选工作目录用）：`{ path, parent, home, entries:[{name,path}] }`，只列目录、跳过隐藏项；path 缺省为主目录 |
| POST | /fs/mkdir | `{ parent, name }` → `{ path }`（201）；名字含路径分隔符或以 . 开头 → 400 |
| GET | /quota?agent=claude\|codex | 账号剩余额度，见下文「用量与额度」 |
| GET | /sessions | 会话列表：手机建的 + 电脑终端里跑过的（见「终端会话导入」），按更新时间倒序 |
| POST | /sessions | `{ agent, cwd, firstMessage?, continueLast?, mode?, model?, effort? }` → Session（201）；cwd 不存在 → 400。旧字段 `yolo:true` 等价 `mode:'trust'` |
| GET | /sessions/:id | 单个会话 |
| PATCH | /sessions/:id | `{ mode?, model?, effort? }` 改会话选项 → Session；`model`/`effort` 传 `null` 或空串恢复默认；广播 `session.updated` |
| DELETE | /sessions/:id | 结束会话 |
| GET | /sessions/:id/messages?after=<messageId> | 增量消息（after 之后的） |
| POST | /sessions/:id/messages | `{ text, attachments?, mode }` → `{ ok, queued, item? }`。`mode`：`auto`（默认，忙就排队）/ `queue` / `now`（插队并打断当前轮）|
| POST | /sessions/:id/stop | 中断当前轮 |
| GET | /approvals?status=pending | 审批列表（手机重启后用它恢复收件箱） |
| POST | /approvals/:id | `{ decision, remember? }`（WS 之外的审批方式）；`remember` 见下 |
| GET | /files?sessionId=&path= | 目录列表 `{ path, entries:[{name,path,kind,size,modifiedAt}] }`，path 相对会话 cwd，越界 403 |
| GET | /files/stat?sessionId=&path= | 单个文件元信息 `{ name, path, displayPath, kind, size, modifiedAt, mime, textual, inCwd }`，文件查看器用 |
| GET | /files/preview?sessionId=&path= | 文本/图片预览（≤ 2MB） |
| GET | /files/download?sessionId=&path= | 下载，带 content-length 与 content-disposition |

### 文件可访问范围
`/files/stat`、`/files/preview`、`/files/download` 的 `path` 可以是相对会话 cwd 的路径，也可以是绝对路径或 `~/…`。放行规则：

1. 会话工作目录内 → 放行（`inCwd: true`，与原有行为一致）
2. 工作目录外、但在用户主目录内且不属于敏感清单 → 放行（`inCwd: false`，聊天正文里点 `~/.yzvibe/pairing.txt` 这类路径要用）
3. 其余（主目录之外、或命中敏感清单）→ 403

敏感清单：`.ssh` `.gnupg` `.aws` `.kube` `Library/Keychains` `.netrc` `.npmrc` `.pypirc` `id_rsa` 等私钥、`*.credentials.json`、`credentials` `.docker/config.json` `.config/gh` `.git-credentials`。
`/files`（目录列表）仍然只在工作目录内。手机端只读取内容，不执行文件。
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
{ "type": "tool.call",          "sessionId": "s1", "messageId": "m9", "toolId": "t1", "name": "Bash", "input": {...},
  "state": "running|done|error", "output": "PASS 12 tests", "outputKind": "text|diff", "truncated": false }
{ "type": "approval.requested", "sessionId": "s1", "approvalId": "a1", "kind": "shell|write|network|other", "summary": "rm -rf dist",
  "detail": "...", "risk": "low|medium|high", "expiresAt": "...", "toolName": "Bash",
  "suggestions": [{ "label": "总是允许 npm test 开头的命令", "match": "prefix", "value": "npm test", "scope": "session", "ttlMinutes": null }] }
{ "type": "message.added",      "sessionId": "s1", "message": { ...Message } }   // 系统消息（规则自动放行等）
{ "type": "approval.resolved",  "approvalId": "a1", "decision": "allow|deny|allow_once", "by": "phone|desktop" }
```
### 客户端 → 服务端
```jsonc
{ "type": "message.send",     "sessionId": "s1", "text": "...", "attachments": ["upload-id"], "mode": "auto|queue|now" }
{ "type": "message.cancel",   "sessionId": "s1", "itemId": "q1" }
{ "type": "session.stop",     "sessionId": "s1" }
{ "type": "session.resume",   "sessionId": "s1" }
{ "type": "session.configure","sessionId": "s1", "mode": "plan", "model": "opus", "effort": "high" }   // 同 PATCH /sessions/:id
{ "type": "approval.respond", "approvalId": "a1", "decision": "allow|deny|allow_once",
  "remember": { "match": "tool|prefix|exact", "value": "npm test", "scope": "session|global", "ttlMinutes": 60 } }
{ "type": "ping" }
```
`decision` 只对这一次生效。要「以后别再问」必须同时给 `remember`，它会在连接器上存成一条规则
（`~/.yzvibe/rules.json`），命中时聊天里会留一条「已按规则自动允许」的系统消息。
`approval.requested` 事件里带 `suggestions`，是连接器算好的几个 `remember` 备选，手机直接渲染成按钮。

## 数据模型（三端共用）
```ts
type Device  = { id, name, host, port, mode: 'tunnel'|'local'|'p2p'|'tailscale'|'relay', online: boolean, lastSeen }
type Session = { id, deviceId, agent: 'claude'|'codex'|string, cwd, title, status, createdAt, updatedAt, mode: 'plan'|'normal'|'trust', model: string|null, effort: string|null, usage: SessionUsage|null, source: 'phone'|'terminal'|'sdk', branch: string|null }
type SessionUsage = { model, turn: TurnUsage, total: { input, cacheWrite, cacheRead, output, thinking, costUSD|null, turns }, updatedAt }
type TurnUsage = { model, input, cacheWrite, cacheRead, output, thinking, contextTokens, contextWindow, costUSD|null, durationMs|null }
type Message  = { id, sessionId, role: 'user'|'assistant'|'tool'|'system', text, attachments?, toolCalls?, approvalId?, ruleId?, createdAt, streaming }
type ToolCall = { id, name, detail, state: 'running'|'done'|'error', output?, outputKind: 'text'|'diff', truncated }
type Rule     = { id, scope: 'session'|'global', sessionId?, agent?, tool?, match: 'tool'|'prefix'|'exact', value?, createdAt, expiresAt?, hits }
type Approval= { id, sessionId, deviceId, kind: 'shell'|'write'|'network'|'other', summary, detail, risk, status: 'pending'|'allowed'|'denied'|'expired', createdAt, expiresAt? }
```

## 三种配对方式（都用同一枚一次性配对码）
1. **扫码**：终端里的二维码，内容是 `yzvibe://pair?host=&port=&token=&mode=&name=`。
2. **外链**：`GET /pair?token=<配对码>` 是公开落地页（HTML），手机浏览器打开后自动跳 `yzvibe://pair?…` 唤起 App，并附「打开 App」按钮与可复制的 JSON。看落地页不消费配对码；配对码错误或过期返回 410。
3. **粘贴 JSON**：`GET /pair.json?token=<配对码>`（同样公开）返回完整配置，App「设备 › 手动添加 › 粘贴配置」可直接粘贴：
```json
{ "yzvibe": 1, "name": "Mac", "host": "https://xxx.trycloudflare.com", "port": null,
  "token": "…", "mode": "tunnel", "connectorId": "…", "version": "0.1.0", "expiresAt": "…",
  "url": "yzvibe://pair?…", "link": "https://xxx.trycloudflare.com/pair?token=…" }
```
`host` 含 `://` 时 `port` 为 null（relay / tunnel 直接用该地址）；局域网 / Tailscale 则 `host` 是裸地址、`port` 单独给出。
App 端 `PairingPayload(text:)` 四种输入通吃：深链、外链、JSON、以及夹在说明文字里的上述任意一种。

## 连接器本机内部接口（不对手机开放）
- `POST /internal/approval`、`GET /internal/status`：只接受带 `X-YzVibe-Secret` 的本机请求，secret 每次启动随机生成，写在 `~/.yzvibe/daemon.json`（0600）。
- `GET /internal/status` → `{ pid, name, version, port, uptime, host, mode, pairing: { token, expiresAt, url }, stats: { devices, sessions, running, pendingApprovals } }`，供 `yzvibe status / qr` 使用（`pairing` 含 `token / expiresAt / url / link / config`）；配对码过期时这里会自动换新，因此连接器常驻后台也随时能配对。

## 地址稳定性

`GET /health` 与配对配置里都带 `endpoints`：连接器所有可达地址（隧道 / Tailscale / 局域网 / 回环）。
手机主地址连不上时依次探活 `/health`（比对 `connectorId`，防止连到别的电脑），成功后把它作为新的主地址存下来。
连接器启动时、以及 Cloudflare 临时隧道重连后，会给所有注册过推送的手机发一条静默推送：

```jsonc
{ "aps": { "content-available": 1 },
  "yz": { "kind": "endpoint", "connectorId": "…", "name": "Mac",
          "endpoints": ["https://新地址", "http://192.168.1.5:19876"], "reason": "tunnel-reconnect" } }
```

同一 Wi-Fi 下连接器还会用 Bonjour 广播 `_yzvibe._tcp`（TXT 带 `id=<connectorId>`）。
设备 Token 一直有效，所以只要地址找得回来就不必重新扫码。

## 锁屏 / 灵动岛实时活动

手机 `POST /devices/live-activity` 交出活动的推送 token 后，连接器在会话状态变化时直接推：

```jsonc
// headers: apns-push-type: liveactivity, apns-topic: <bundleId>.push-type.liveactivity
{ "aps": { "timestamp": 1789050000, "event": "update", "stale-date": 1789050600,
           "content-state": { "status": "running", "headline": "正在 Bash：npm test",
                              "pendingApprovals": 0, "queued": 2, "contextPercent": 37,
                              "updatedAt": 810742800 } } }
```

`updatedAt` 是 Swift `Date` 的默认编码（自 2001-01-01 起的秒数），不是 ISO8601。会话闲下来推一条 `event: "end"`。

## 远程推送（APNs）
连接器直连 `api.push.apple.com`，配置在 `~/.yzvibe/apns.json`（`keyFile` / `keyId` / `teamId` / `bundleId` / `environment`）。
手机通过 `POST /devices/push` 交出 token，连接器在这些时机推送：

| 时机 | 载荷 | 说明 |
|---|---|---|
| 有待审批 | `interruption-level: time-sensitive`，`yz.kind = "approval"`，带角标与 `collapse-id` | 锁屏也能收到，点开直接进审批 |
| 回复完成且没有手机在线 | `interruption-level: active`，`yz.kind = "reply"` | 手机连着时不推，App 自己会显示 |
| 审批被解决 | 静默推送（`content-available`），只更新角标 | |

设备 token 报 `BadDeviceToken` 时自动换另一个环境重试，`Unregistered` 时清掉。没配置密钥就整体不推送。

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

## 终端会话导入

连接器把本机 CLI 里已经进行过的会话也列出来（`connector/src/transcripts.js`），手机上可以直接接着聊：
- Claude Code：`~/.claude/projects/<cwd 编码>/<sessionId>.jsonl`（`CLAUDE_CONFIG_DIR` 可改）。标题取 `ai-title`，没有则取第一条用户消息；`cwd` / `gitBranch` / `entrypoint` 来自记录头。`entrypoint = cli` → `source: terminal`，其他（SDK / 其他工具的 headless 调用）→ `sdk`。
- Codex：`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`（`CODEX_HOME` 可改）。标题取第一条 `user_message`，`cwd` 来自 `session_meta`。
- 列表阶段只读文件头（最近 45 天、每种 Agent 最多 80 个文件，按 mtime 缓存）；id 形如 `claude:<sessionId>` / `codex:<threadId>`。
- 手机第一次访问某个终端会话（取消息、发消息、改选项）时连接器**接管**它：以同一 id 入库、把 transcript 翻译成消息历史（最多 300 条，工具调用变成工具卡），之后发消息走 `--resume <sessionId>` / `codex exec resume <threadId>`，与手机自建会话无异。接管后列表里不再重复。
- 已被本连接器创建的会话（agentSessionId 已知）不会被当成终端会话重复列出。`createConnector({ importTerminal: false })` 可关闭。
- Codex 额度：`GET /quota?agent=codex` 从最近的 rollout 里的 `token_count.rate_limits` 取（5 小时 / 本周窗口），带 `warning` 说明不是实时值。


## 可靠性行为补充

- Session 新增 `queuePaused: boolean`；队列项新增 `deliveryState`（`queued` / `dispatching` / `uncertain`），旧数据缺省为 queued。
- 重启后保留队列并暂停，原 dispatching 转为 uncertain。`POST /sessions/:id/queue/resume` 主动恢复并返回 Session；有 uncertain 项时返回 409，需先检查历史并通过原 DELETE 队列接口移除该项。
- 手动停止、Agent 错误会暂停尚未发送的队列。拒绝单个工具审批不代表整轮已结束，只有 Agent 回到 idle 才推进队列。
- iOS 恢复前台时对已打开会话读取完整消息快照，更新原有消息与工具结果；原 `after` 查询仍可供只需增量追加的调用方使用。
- HTTP 读取请求可在验证 connectorId 后切换一次候选地址；写请求失败不会自动重放。
- 工作区 diff 中已暂存与未暂存改动以分节文本展示；会话范围包含基线 commit 以来的已提交修改。
