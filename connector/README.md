# yzvibe 桌面连接器

在跑任务的电脑上运行，把本机的 Claude Code 会话暴露给手机 App。协议见 `../shared/protocol.md`。

```bash
cd connector && npm install
node bin/yzvibe.js                      # 默认：Cloudflare Tunnel（需要 cloudflared；没有则退回局域网）
node bin/yzvibe.js --access=local       # 只在局域网配对
node bin/yzvibe.js --access=https://x   # 使用自己的 relay（cloudflared / ngrok）
node bin/yzvibe.js --access=100.64.1.2  # Tailscale IP
node bin/yzvibe.js --agent=codex        # 新会话默认用 Codex CLI（手机新建会话时也可单独选 Claude / Codex）
node bin/yzvibe.js --agent=mock         # 不调用 Claude，用内置假 Agent 演示完整流程
```

默认端口 19876（`--port=` 或环境变量 `YZVIBE_PORT` 可改）；被占用时自动向后找空闲端口。

启动后终端打印二维码，手机 App「设备 › 扫码配对」扫一次即可。二维码 10 分钟有效、一次性。

## 工作原理
- `src/server.js`：HTTP REST + WebSocket，Bearer Token 鉴权，事件广播
- `src/store.js`：会话 / 消息 / 审批 / 设备，持久化到 `~/.yzvibe/`
- `src/agents/claude.js`：`claude -p --input-format stream-json --output-format stream-json` 驱动，多轮复用同一进程，`--resume` 恢复；手机改了模式 / 模型 / 思考强度后在空闲时重启进程带新参数
- `src/agents/codex.js`：`codex exec --json` 驱动，每轮一个进程，`codex exec resume <thread>` 续聊；非交互模式没有审批回调，Normal 靠 workspace-write 沙箱兜底
- `src/agents/options.js`：Plan / Normal / Trust、模型、思考强度在两种 Agent 上的参数映射与能力表（`GET /agents`），详见 `../shared/protocol.md`「会话选项」
- `src/mcp-approve.js`：最小 MCP 服务器；Claude 通过 `--permission-prompt-tool mcp__yzvibe__approve` 把权限请求交给它，它转发到手机等待批准
- `src/agents/mock.js`：演示用假 Agent（流式回复 → 工具调用 → 高风险审批 → 完成）
- `src/files.js`：只读文件列表 / 预览 / 下载，限制在会话工作目录内

## 测试
```bash
npm test     # 端到端：配对 → 会话 → WS 流式 → 审批 → 自动放行 → 文件 → 上传；会话选项 PATCH / 能力表；Codex 事件解析
```
