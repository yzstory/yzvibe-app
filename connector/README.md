# yzvibe 桌面连接器

在跑任务的电脑上运行，把本机的 Claude Code 会话暴露给手机 App。协议见 `../shared/protocol.md`。

```bash
npx yzvibe                               # 直接跑；或从仓库里：cd connector && npm install
node bin/yzvibe.js                       # = start：后台启动（Cloudflare Tunnel，缺 cloudflared 退回局域网）并打印二维码
node bin/yzvibe.js start --access=local  # 只在局域网配对
node bin/yzvibe.js start --access=https://x   # 使用自己的 relay（cloudflared / ngrok）
node bin/yzvibe.js start --access=100.64.1.2  # Tailscale IP
node bin/yzvibe.js start --agent=codex   # 新会话默认用 Codex CLI（手机新建会话时也可单独选）
node bin/yzvibe.js start --agent=mock    # 不调用 Claude，用内置假 Agent 演示完整流程
```

## 后台运行

`start` 会把连接器放到后台（`~/.yzvibe/daemon.json` 记录 PID / 端口 / 地址），打印二维码后就退出，终端可以关掉：

| 命令 | 作用 |
|---|---|
| `yzvibe start [flags]` | 后台启动并出示二维码；已在运行则只出示二维码（默认命令） |
| `yzvibe run [flags]` | 前台运行，Ctrl+C 退出（调试用） |
| `yzvibe status` | PID、地址、模式、会话数、已配对手机数 |
| `yzvibe qr` | 再次出示三种配对方式：二维码 + 手机浏览器外链 + 可粘贴的 JSON 配置；配对码 10 分钟一次性，过期自动换新，不用重启（`--link` / `--json` 只输出一项，便于管道） |
| `yzvibe logs [-f] [-n 100]` | 查看 `~/.yzvibe/yzvibe.log`（超过 5MB 自动轮转到 `.1`） |
| `yzvibe stop` / `restart [flags]` | 停止 / 用上次的参数（或新参数）重启 |
| `yzvibe devices` | 列出已配对的手机：id、名字、配对时间、是否注册了推送 |
| `yzvibe revoke <id\|名字>` | 吊销某台手机：Token 立即失效，正在连的连接会被踢掉 |
| `yzvibe push [--test]` | 看推送配置状态；`--test` 给所有已注册的手机发一条自检推送 |
| `yzvibe install [flags]` / `uninstall` | 注册 / 取消开机自启：macOS 写 `~/Library/LaunchAgents/com.yzvibe.connector.plist`（KeepAlive，崩溃自动拉起），Linux 写 systemd `--user` 单元 |

### 三种配对方式

`yzvibe qr` 一次给出三种，任选其一：

1. **扫码** — 终端里的二维码。
2. **外链** — 形如 `https://<relay>/pair?token=…`（局域网则是 `http://<ip>:<port>/pair?token=…`）。手机浏览器打开会自动唤起 App 完成配对；页面同时给出「打开 App」按钮与可复制的 JSON，App 没装或没跳转时也不会卡住。
3. **JSON 配置** — `yzvibe qr --json`，在 App「设备 › 手动添加 › 粘贴配置」里粘贴即可，字段自动填好。

落地页 `GET /pair` 与 `GET /pair.json` 是公开路由（凭据就是 URL 里的一次性配对码），查看它们不会消费配对码；配对码错误或过期返回 410。

Cloudflare 临时隧道进程退出，或日志出现 `Unauthorized: Tunnel not found` 时，连接器会重建隧道；失败后按 5 / 10 / 20 / 40 / 60 秒退避持续重试。普通网络断开由 cloudflared 自身重连，避免不必要地更换地址。

临时地址重建后会变化。已配置 APNs 且手机注册推送时会尝试下发新地址，但静默推送不保证送达；同一 Wi-Fi 下可在设备页选择「在局域网里找」，保留原配对。异地且没有可达备用地址或推送时，手机无法凭旧地址发现新地址，仍需更新地址或扫码。

长期使用建议配置有固定域名的 Cloudflare Tunnel，再运行 `yzvibe restart --access=https://<固定域名>`，将隧道源站指向 `http://localhost:19876`（自定义端口时相应调整）。此选项只配置连接器公布的地址，不会创建或托管命名隧道；cloudflared 服务需要独立运行。首次迁移固定地址可重新扫码一次，之后短暂断线无需重新配对。Quick Tunnel 官方说明：https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/ 。

默认端口 19876（`--port=` 或环境变量 `YZVIBE_PORT` 可改）；被占用时自动向后找空闲端口。数据目录可用 `YZVIBE_HOME` 覆盖。

## 远程推送（APNs）

App 被 iOS 挂起后 WebSocket 一定会断，只有远程推送能把待审批送到锁屏上。连接器直连 `api.push.apple.com`，不经第三方。

配置 `~/.yzvibe/apns.json`（把 `AuthKey_XXXXXXXXXX.p8` 放进 `~/.yzvibe/` 后 `keyId` 会自动从文件名推断）：

```json
{ "teamId": "TRVTR5HQP8", "bundleId": "icu.yzvibe.YzVibe", "environment": "sandbox" }
```

`environment`：Xcode 直接装到手机的是 `sandbox`，TestFlight / App Store 是 `production`。填错也没关系——
连接器收到 `BadDeviceToken` 会自动换另一个环境重试，成功后记住；token 失效（`Unregistered`）会自动清掉。

推送时机：有待审批时（`time-sensitive`，带角标）；回复完成且手机没连着时；审批被解决时发一条静默推送更新角标。
没配置就整体降级为不推送，其余功能不受影响。`yzvibe push` 看状态，`yzvibe push --test` 发一条自检。

## 消息队列

Agent 正忙时收到的消息不会被丢掉也不会打断它：进队列（`session.queue`），本轮回到 `idle` 就自动发出去。
`POST /sessions/:id/messages` 的 `mode`：`auto`（默认，忙就排队）、`queue`（强制排队）、`now`（插到队首并打断当前轮）。
`DELETE /sessions/:id/queue/:itemId` 撤掉一条。队列变化通过 `session.updated` 广播，手机上显示成「排队中」的虚线气泡。

实测：Claude Code 的 stream-json 输入本身不排队（多写一行只会变成下一轮），也没有中断用的控制消息，
所以打断只能靠 SIGINT，队列与「排队中」这个可见状态都由连接器提供。

## 会话改动与命令清单

- `GET /sessions/:id/diff?scope=working|session`：`git status` + `git diff` 整理成按文件分块的结构，
  新文件直接给全文（全是 + 行）。`scope=session` 跟会话创建时记下的 `baseCommit` 比。
  不是 git 仓库时返回 `{repo:false, reason}`，手机上会显示一句说明而不是空白页。
- `GET /sessions/:id/commands`：手机端命令 + Agent 斜杠命令 + skill。
  Claude 的清单以它在 `system.init` 里自报的 `slash_commands` 为准（去掉 `terminal_slash_commands`，
  实测 64 个里只有 doctor / color / reload-plugins 是终端专用），拿不到时退回扫盘：
  `~/.claude/skills/*/SKILL.md`（常是符号链接，要用 statSync 判断目录）、项目 `.claude/skills/`、
  插件 `installed_plugins.json` 里的 `installPath`，以及 `~/.claude/commands/*.md`。
  Codex 读 `~/.codex/skills/`；手机命令目录和技能入口继续保留，带 `insertAsText` 的条目仍按提示词发送。

## 锁屏 / 灵动岛实时活动

手机开活动时把它的推送 token 交给 `POST /devices/live-activity`，之后会话每次状态变化，
连接器直接推一条 `apns-push-type: liveactivity`（topic 是 `<bundleId>.push-type.liveactivity`），
App 被挂起也能刷新。新版使用 `overview:<connectorId>` 汇总当前电脑的运行和待审批任务，
长按展开最多显示 3 条，待审批优先，超出时显示剩余数量；点击任务可回到对应会话。
只有最后一个任务结束才推 `event: "end"` 收尾，旧版单会话 token 仍兼容。
运行提示使用系统计时文本和状态更新动画；实时活动首次由前台 App 创建，后台通过 APNs 更新。
注意 `content-state` 里的 `Date` 要用 Swift 的默认编码（自 2001-01-01 起的秒数），不是 ISO8601。

## 换了地址也不用重新扫码

Cloudflare 的临时隧道每次重开都是新地址，电脑一重启手机就连不上。三重兜底：

1. `GET /health` 与配对配置都带 `endpoints`：隧道 / Tailscale / 局域网 / 回环全报出去，手机主地址失败就依次探活。
2. 启动时和隧道重连后，给注册过推送的手机静默推一条新地址（`yz.kind = "endpoint"`）。
3. 同一 Wi-Fi 下用 Bonjour 广播 `_yzvibe._tcp`（macOS 走 dns-sd，Linux 走 avahi-publish；都没有就跳过）。

设备 Token 本来就长期有效，所以只要地址找得回来就不必重新配对。

## 审批规则

`~/.yzvibe/rules.json`。手机在审批卡上点「总是允许…」时创建，三种匹配方式：

| match | 含义 | 例子 |
|---|---|---|
| `tool` | 这个工具都放行 | 本会话 1 小时内不再询问 `Bash` |
| `prefix` | 命令前缀匹配 | 放行所有 `npm test` 开头的命令 |
| `exact` | 完全相同的命令 | 只放行这一条 |

`scope` 为 `session`（只在这个会话里）或 `global`（所有会话）；`ttlMinutes` 到期自动失效。
命中规则时会在聊天里留一条「已按规则自动允许」，不会悄悄执行。`GET /rules` 查、`DELETE /rules/:id` 撤销。

## 定期清理

连接器长期后台运行，这些东西只增不减，所以每 6 小时清一次（启动时也清一次）：

- 上传的图片：14 天前的删掉（旧聊天里的图会显示「图片不可用」）
- 已关闭且 45 天没动的会话：删消息文件并从列表里移除
- 孤儿消息文件、上次异常退出留下的 `mcp-*.json`
- 日志超过 5MB 轮转

Claude 进程也会回收：会话空闲 15 分钟（`YZVIBE_IDLE_MINUTES` 可改，0 = 不回收）就结束它，
下次发消息用 `--resume` 无损接回。开十几个会话不会再常驻十几个 Node 进程。

## 工作原理
- `src/server.js`：HTTP REST + WebSocket，Bearer Token 鉴权，事件广播；`/pair` 落地页与 `/pair.json` 配置；`/internal/status` 供本机 CLI 取配对码与统计
- `src/pairing.js`：一次性配对码、二维码、深链 / 外链 / JSON 配置、浏览器落地页
- `src/daemon.js`：后台守护（daemon.json、日志轮转、start/stop/status、launchd / systemd 注册）
- `src/store.js`：会话 / 消息 / 审批 / 设备（含推送 token），持久化到 `~/.yzvibe/`
- `src/push.js`：APNs（ES256 JWT + HTTP/2），环境自动回退、失效 token 自动清理
- `src/rules.js`：审批规则的匹配、持久化与「总是允许」建议
- `src/cleanup.js`：上传 / 旧会话 / 孤儿文件的定期清理
- `src/diff.js`：行级 diff，把 Edit / Write 的改动变成手机上能看的 +/- 文本
- `src/git.js`：工作目录的改动概览（状态 / 行数 / 按文件分块的 diff / 新文件全文）
- `src/commands.js`：斜杠命令与 skill 的发现与归类
- `src/endpoints.js`：所有可达地址的收集与 Bonjour 广播
- `src/agents/claude.js`：`claude -p --input-format stream-json --output-format stream-json` 驱动，多轮复用同一进程，`--resume` 恢复；手机改了模式 / 模型 / 思考强度后在空闲时重启进程带新参数；空闲超时回收进程。事件翻译独立成 `ClaudeStreamTranslator`，可用录制的事件流直接测试
- `src/agents/codex-app-server.js` / `codex-rpc.js`：Codex App Server stdio 驱动；原线程续聊、流式文本、工具事件、手机审批与提问表单。每轮结束释放连接，下一轮重新恢复线程并应用最新选项。
- `src/agents/codex.js`：保留旧 exec 事件解析及测试，不再作为默认驱动。
- `src/agents/options.js`：Plan / Normal / Trust、模型、思考强度在两种 Agent 上的参数映射与能力表（`GET /agents`），详见 `../shared/protocol.md`「会话选项」
- `src/mcp-approve.js`：最小 MCP 服务器；Claude 通过 `--permission-prompt-tool mcp__yzvibe__approve` 把权限请求交给它，它转发到手机等待批准
- `src/agents/mock.js`：演示用假 Agent（流式回复 → 工具调用 → 高风险审批 → 完成）
- `src/files.js`：只读文件列表 / 元信息 / 预览 / 下载。目录列表限制在会话工作目录内；单个文件还允许读主目录里的非敏感文件（聊天里点 `~/.yzvibe/pairing.txt` 这种路径用），私钥 / 凭据一律 403
- `src/transcripts.js`：扫描 `~/.claude/projects` 与 `~/.codex/sessions`，把终端里跑过的会话列进会话列表；手机打开时翻译历史并接管（之后 `--resume` 续聊）
- `src/quota.js`：账号额度，Claude 走 `api/oauth/usage`（本机钥匙串 token），Codex 取最近 rollout 里的 rate_limits

## 测试
```bash
npm test     # 41 个用例
```

覆盖：配对（扫码 / 外链 / JSON，过期换新）、会话与 WS 流式、审批与规则自动放行、文件权限边界、
会话选项与能力表、Claude 事件流翻译（录制夹具）、Codex 事件解析、用量与额度归一、
APNs JWT 与载荷、推送环境回退与失效清理、实时活动载荷、`/sync`、设备撤销、定期清理、
消息队列（排队 / 取消 / 本轮结束自动接上）、改动视图与命令清单、多地址上报、后台守护真实拉起子进程。


## Codex App Server

需要安装支持 `codex app-server` 的 Codex CLI（已用 0.153.4 实测）。沿用本机 Codex 登录、配置、MCP 与技能，无需新的 API key，也不在网络上暴露 App Server 端口。

- Normal：`workspace-write` + `on-request`；工作目录内按沙箱执行，额外权限请求进入现有手机审批卡片和 APNs 推送。允许只批准当前请求，已保存的命令规则仍生效。
- Plan：只读沙箱与规划提示，禁止提权；Trust：沿用无沙箱、免审批模式。
- 旧会话使用原 `agentSessionId` 恢复，不复制线程；手机显示名称、消息、附件、草稿、队列等存储不变。原线程恢复失败会明确报错，不会偷偷另建会话。
- 排队由连接器统一管理；收到 `turn/completed` 后推进。立即发送沿用打断当前轮、优先派发的交互。中断未确认、断线和发送结果不明时暂停队列，不自动重发。
- 命令、文件修改、额外权限请求可在手机审批；`request_user_input` 在新版 App 的审批区域显示选项和文本框。拒绝、超时、停止、删除或断线均使旧审批失效。
- 当前上下文直接取 `thread/tokenUsage/updated.last`，与整轮累计分开显示。
- 需要额外专用界面的 MCP elicitation（例如第三方登录表单）会明确提示并拒绝请求，不会自动同意或一直挂起；可回电脑完成。普通 MCP 工具不受此限制。

升级：更新连接器代码后运行 `yzvibe restart`；现有配对与数据保留。手机 Normal 的允许／拒绝兼容现有版本，提问表单与更完整的实时事件需要新版 iOS App。运行中的会话应结束后再重启连接器。
