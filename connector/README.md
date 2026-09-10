# yzvibe 桌面连接器

在跑任务的电脑上运行，把本机的 Claude Code 会话暴露给手机 App。协议见 `../shared/protocol.md`。

```bash
cd connector && npm install
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
| `yzvibe qr` | 再次出示配对二维码；配对码 10 分钟一次性，过期自动换新，不用重启 |
| `yzvibe logs [-f] [-n 100]` | 查看 `~/.yzvibe/yzvibe.log`（超过 5MB 自动轮转到 `.1`） |
| `yzvibe stop` / `restart [flags]` | 停止 / 用上次的参数（或新参数）重启 |
| `yzvibe install [flags]` / `uninstall` | 注册 / 取消开机自启：macOS 写 `~/Library/LaunchAgents/com.yzvibe.connector.plist`（KeepAlive，崩溃自动拉起），Linux 写 systemd `--user` 单元 |

Cloudflare 临时隧道断开时连接器会自动重开一条并写进日志；临时隧道地址会变，手机需重新扫码（`yzvibe qr`）。想要固定地址请用 `--access=https://<自己的隧道>`。

默认端口 19876（`--port=` 或环境变量 `YZVIBE_PORT` 可改）；被占用时自动向后找空闲端口。数据目录可用 `YZVIBE_HOME` 覆盖。

## 工作原理
- `src/server.js`：HTTP REST + WebSocket，Bearer Token 鉴权，事件广播；`/internal/status` 供本机 CLI 取配对码与统计
- `src/daemon.js`：后台守护（daemon.json、日志轮转、start/stop/status、launchd / systemd 注册）
- `src/store.js`：会话 / 消息 / 审批 / 设备，持久化到 `~/.yzvibe/`
- `src/agents/claude.js`：`claude -p --input-format stream-json --output-format stream-json` 驱动，多轮复用同一进程，`--resume` 恢复；手机改了模式 / 模型 / 思考强度后在空闲时重启进程带新参数
- `src/agents/codex.js`：`codex exec --json` 驱动，每轮一个进程，`codex exec resume <thread>` 续聊；非交互模式没有审批回调，Normal 靠 workspace-write 沙箱兜底
- `src/agents/options.js`：Plan / Normal / Trust、模型、思考强度在两种 Agent 上的参数映射与能力表（`GET /agents`），详见 `../shared/protocol.md`「会话选项」
- `src/mcp-approve.js`：最小 MCP 服务器；Claude 通过 `--permission-prompt-tool mcp__yzvibe__approve` 把权限请求交给它，它转发到手机等待批准
- `src/agents/mock.js`：演示用假 Agent（流式回复 → 工具调用 → 高风险审批 → 完成）
- `src/files.js`：只读文件列表 / 预览 / 下载，限制在会话工作目录内
- `src/transcripts.js`：扫描 `~/.claude/projects` 与 `~/.codex/sessions`，把终端里跑过的会话列进会话列表；手机打开时翻译历史并接管（之后 `--resume` 续聊）
- `src/quota.js`：账号额度，Claude 走 `api/oauth/usage`（本机钥匙串 token），Codex 取最近 rollout 里的 rate_limits

## 测试
```bash
npm test     # 端到端：配对 → 会话 → WS 流式 → 审批 → 自动放行 → 文件 → 上传；会话选项 PATCH / 能力表；Codex 事件解析
```
