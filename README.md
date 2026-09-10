# YzVibe

**离开电脑，AI 会话照样往前推。**

YzVibe 把手机变成桌面 AI 编程会话（Claude Code 等）的遥控器：发消息、看进度、审批敏感操作、取文件。会话始终跑在你自己的电脑上，无账号、无云端、手机不执行任何代码。

产品形态参考 [Vibelet](https://vibelet.icu/zh/)，视觉为 iOS 26 液态玻璃 × 暖调纸感配色。

- 设计画布（Claude Design）：https://claude.ai/code/artifact/d168c7db-23fa-426c-ad13-2b5bce984f41

## 它是怎么工作的

```
┌──────────────┐  HTTPS / WebSocket   ┌──────────────────┐   stream-json    ┌─────────────┐
│  手机 App     │ ◄──────────────────► │  桌面连接器        │ ◄─────────────► │ Claude Code │
│  iOS（已实现）│  Tunnel / LAN / TS   │  npx yzvibe       │   MCP 审批桥     │ Codex …     │
│  Android/小程序（预留）│              │  Node.js           │                 └─────────────┘
└──────────────┘                      └──────────────────┘
```

1. 电脑上运行 `npx yzvibe`，终端打印一次性二维码
2. 手机 App 扫码配对（也可以用手机浏览器打开终端给的外链自动唤起 App，或把 `yzvibe qr --json` 的 JSON 粘进 App），之后随时重连
3. 新建会话（选 Agent 与工作目录）→ 发指令 → 看流式回复、工具调用与它们的真实输出
4. Claude 需要执行敏感操作时，手机收到审批卡：允许 / 拒绝，或「总是允许…」把它变成一条规则（高风险可要求 Face ID）
5. 配好远程推送后，锁屏也能收到审批；点开直接进到那条请求
6. 需要时浏览远程文件、预览、按需下载；发图片给会话

## 仓库结构

```
YzVibe/
├─ docs/
│  ├─ PRD.md            产品需求：定位、用户、功能矩阵（MoSCoW）、信息架构、流程、里程碑
│  └─ DESIGN.md         设计规范：oklch 颜色 token、玻璃配方、字阶、组件、三端映射
├─ shared/protocol.md   手机 ⇄ 连接器协议（REST + WebSocket + 数据模型），三端共用
├─ connector/           桌面连接器（Node.js）：REST/WS、配对二维码、Claude Code 驱动、MCP 审批桥
├─ ios/                 SwiftUI 实现：YzVibeKit 库 + App 壳 + XcodeGen
├─ design/canvas/       设计画布源文件（build.py 生成 10 块画板）
├─ android/             预留：Kotlin + Compose
├─ miniprogram/         预留：微信小程序
└─ task_plan.md / findings.md / progress.md   规划与研究记录
```

## 快速开始

### 1. 连接器（电脑）
```bash
npx yzvibe                               # 后台启动（Cloudflare Tunnel）并打印二维码，终端可以直接关掉
# 或者从仓库里跑：
cd connector && npm install
node bin/yzvibe.js                       # 等价于 npx yzvibe
node bin/yzvibe.js start --access=local  # 局域网
node bin/yzvibe.js start --agent=mock    # 没有 Claude 也能演示完整流程
node bin/yzvibe.js qr / status / logs -f / stop / restart
node bin/yzvibe.js devices / revoke <手机>  # 看已配对的手机 / 吊销某一台
node bin/yzvibe.js push [--test]         # 远程推送配置与自检
node bin/yzvibe.js install               # 注册开机自启（macOS launchd），崩溃自动拉起
```
连接器默认在后台运行，`run` 子命令才是前台（Ctrl+C 退出）。需要本机已安装并登录 `claude` CLI。会话数据与日志保存在 `~/.yzvibe/`。

### 2. iOS App
```bash
brew install xcodegen
cd ios && xcodegen generate && open YzVibe.xcodeproj
```
真机运行后：设备 › 扫码配对 → 扫终端里的二维码。没有连接器时可点「先看看演示数据」。

只编译库、跑测试（不需要生成工程）：
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift build --package-path ios --build-tests \
  --triple arm64-apple-ios17.0-simulator \
  --sdk "$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun --sdk iphonesimulator --show-sdk-path)"
```

### 3. 连接器测试
```bash
cd connector && npm test
```

## 连接方式

| 方式 | 命令 | 说明 |
|---|---|---|
| Cloudflare Tunnel（默认） | `npx yzvibe` | 免费免注册，需要 `cloudflared`；隧道断开会自动重连（临时地址会变，需重新扫码） |
| 局域网 | `npx yzvibe --access=local` | 手机与电脑同一 Wi-Fi |
| 自定义 Relay | `npx yzvibe --access=https://<url>` | 已有 cloudflared / ngrok 隧道；地址会保存复用，`--force` 换新 |
| Tailscale | `npx yzvibe --access=<tailscale-ip>` | 手机加入同一 tailnet |

连接器在后台常驻：`yzvibe status` 看状态，`yzvibe qr` 随时再出示配对方式（二维码 / 手机浏览器外链 / 可粘贴的 JSON 配置，配对码过期自动换新），`yzvibe logs -f` 看日志，`yzvibe stop` 停止。`yzvibe install` 注册为 macOS launchd / Linux systemd 用户服务，登录即启动、崩溃自动拉起。

## 远程推送：让「离开电脑」真正成立

iOS 把 App 切到后台几十秒后就会挂起，WebSocket 必然断开。没有远程推送，锁屏之后的审批请求会一直在电脑上等到超时，手机什么都收不到。
连接器**直接连苹果的 APNs**，不经任何第三方服务器。准备一次即可：

1. 苹果开发者后台建一个 APNs 密钥，下载 `AuthKey_XXXXXXXXXX.p8`
2. 把它放进电脑的 `~/.yzvibe/`
3. 写 `~/.yzvibe/apns.json`：`{ "teamId": "你的 TeamID", "bundleId": "icu.yzvibe.YzVibe", "environment": "sandbox" }`
   （Xcode 直接装的调试版填 `sandbox`，TestFlight / App Store 版填 `production`；填错连接器会自动换另一个重试）
4. `yzvibe restart`，然后 `yzvibe push --test` 发一条自检

App 里在「我 › 通知 › 远程推送」能看到每一步的状态。没配置也不影响其它功能，只是锁屏收不到审批。

## 审批是怎么实现的

连接器以 `claude -p --input-format stream-json --output-format stream-json --permission-prompt-tool mcp__yzvibe__approve` 启动 Claude。
Claude 需要权限时调用 MCP 工具 `approve`（`connector/src/mcp-approve.js`），它转发到连接器并等待手机的决定。

审批卡上有两个按钮加一个菜单：

- **允许 / 拒绝** — 只对这一次生效，拒绝的原因会回传给 Claude
- **总是允许…** — 存成一条规则，同类请求以后自动放行。可以按工具（本会话 1 小时内不再问 Bash）或按命令前缀（放行所有 `npm test` 开头的命令）。规则存在连接器的 `~/.yzvibe/rules.json`，在 App「我 › 安全 › 审批规则」里能看到用了多少次，随时撤销

自动放行时聊天里会留一条「已按规则自动允许」的记录，不会悄悄执行。
新建会话选 Trust 模式则改传 `--dangerously-skip-permissions`，完全不产生审批。

## 会话里能看到什么

工具调用不再只显示「运行中 / 完成」：点开工具卡能看到命令的真实输出，`Edit` / `Write` 显示按 +/- 着色的改动 diff。
输出太长会截断中间部分并注明。审批卡里的文件改动同样带 diff，不用先猜再批。

App 回到前台时会立刻重连事件通道，并从「服务端确认过的最后一条消息」往后补齐离线期间的内容，
不会出现「切走再回来，会话停在几分钟前」的情况。

## 设计原则

- **本地优先**：无账号、无云端工作区，数据留在用户机器，Token 存钥匙串
- **审批是第一公民**：独立收件箱 + 远程推送 + Face ID + 可撤销的放行规则
- **一次扫码**：配对 ≤ 10 秒，重连零成本
- **手机不执行代码**：只展示、只转发
- **玻璃只用于漂浮层**：导航、Tab、输入条、审批卡是玻璃；内容卡片永远不透明

## 路线图

| 里程碑 | 内容 | 状态 |
|---|---|---|
| M0 | 规划 + 设计稿 | ✅ |
| M1 | iOS 静态 UI + Mock 数据 | ✅ |
| M2 | 连接器 MVP + iOS 真实联调（协议、审批桥、文件、上传） | ✅ 已在真机上跑通 |
| M3 | APNs 远程推送、断线重同步、工具输出可见、审批规则、资源回收、CI | ✅ 代码完成，推送需自备 APNs 密钥 |
| M4 | Live Activity / 灵动岛、Android、小程序 | ⏳ |

## 许可
MIT
