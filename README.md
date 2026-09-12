<p align="center">
  <img src="docs/assets/yzvibe-logo.png" width="112" height="112" alt="YzVibe Logo：白底小柚子女孩抱着橙色 V" />
</p>
<h1 align="center">YzVibe</h1>
<p align="center"><strong>离开电脑，继续 Vibe。</strong></p>
<p align="center">在 iPhone 上继续电脑里的 AI 编程会话：发指令、看输出、批操作、取文件。</p>
<p align="center">
  <a href="#快速开始">快速开始</a> ·
  <a href="#系统架构">系统架构</a> ·
  <a href="docs/ARCHITECTURE.md">架构详解</a> ·
  <a href="docs/BRAND.md">Logo 与 iOS 图标</a> ·
  <a href="shared/protocol.md">通信协议</a>
</p>

***

YzVibe 是一个本地优先的 AI 编程遥控器。桌面连接器在你的电脑上运行 Claude Code 或 Codex，iOS App 负责交互和展示。你可以在手机上新建会话，也可以打开连接器发现的终端历史会话，接着往下聊。

**无需 YzVibe 账号或自建云端工作区。** 会话记录保存在电脑上，手机不执行代码。Agent 仍通过各自配置的模型服务工作；远程连接可经过隧道，锁屏通知使用 Apple APNs。

## 能做什么

| 能力     | 当前实现                                               |
| ------ | -------------------------------------------------- |
| 随时续聊   | 多设备、多会话；选择 Agent、工作目录、模式、模型和思考强度；恢复终端历史会话          |
| 看清执行过程 | 对话更新、工具状态、交付详情中的真实输出、文件改动 diff、用量与额度信息                 |
| 手机上审批  | Claude / Codex 权限请求进入聊天卡片和审批收件箱；支持拒绝理由、Face ID 确认和可撤销的放行规则 |
| 传图与取文件 | 向会话发送图片；浏览远程目录、预览和下载文件                             |
| 离线后接上  | 前台重连，补齐断线期间的消息；可选 APNs 审批与完成通知                     |
| 日常常驻   | 后台守护、日志轮转、设备撤销、资源清理、macOS / Linux 用户服务             |

**本轮更新**：可靠待发送箱、消息去重与中断恢复；会话「更多 → 任务交付记录」、设备「诊断」。iOS build 11 需配套 Connector 0.1.1，详见 [发布与升级说明](docs/RELEASE-0.1.0-11.md)。

客户端目前为 **SwiftUI / iOS 17+**，iOS 26 使用 Liquid Glass，低版本使用材质模糊。Android 和微信小程序仅预留目录。

### Claude Code 与 Codex 的区别

以下是本仓库驱动的行为，具体映射见 [Claude 选项](connector/src/agents/options.js) 与 [Codex App Server 驱动](connector/src/agents/codex-app-server.js)。

| 会话模式   | Claude Code      | Codex                    |
| ------ | ---------------- | ------------------------ |
| Plan   | 原生规划模式，通过权限桥处理请求 | 只读沙箱 + 规划提示词             |
| Normal | 敏感操作发到手机审批       | 工作目录可写沙箱；额外权限请求发到手机审批 |
| Trust  | 跳过权限检查           | 跳过审批和沙箱                  |

Trust 会允许 Agent 直接执行操作，请在了解其含义后选择。Mock 驱动用于演示与开发，不调用真实模型。

## 系统架构

![1.00](docs/assets/architecture.svg)

1. **配对**：电脑生成一次性配对码，手机扫码、打开配对链接或粘贴 JSON，换取设备 Token。
2. **执行**：手机通过 REST 发指令，连接器在指定工作目录启动本地 Agent；输出经 WebSocket 返回。
3. **审批**：Claude 经 MCP 审批桥提出请求，连接器匹配放行规则，或等待手机决定。
4. **恢复**：手机回到前台后重新连接并同步遗漏内容；配置 APNs 后可在锁屏接收通知。

组件职责、审批时序和数据边界见 [架构详解](docs/ARCHITECTURE.md)。

## 快速开始

### 1. 在电脑上启动连接器

需要 **Node.js 20+**。使用真实 Agent 前，先在电脑安装并登录对应的 `claude` 或 `codex` CLI，确认能在目标工作目录正常运行。

在仓库根目录执行：

```bash
cd connector
npm install

# 同一 Wi-Fi 下连接，后台启动并展示配对二维码
node bin/yzvibe.js start --access=local
```

也可以选择以下启动方式；如果连接器已经运行，使用 `restart` 应用新参数：

```bash
# Cloudflare 临时隧道；需要 cloudflared，缺失时回落局域网
node bin/yzvibe.js start

# 默认使用 Codex（也可在手机新建会话时选择）
node bin/yzvibe.js start --access=local --agent=codex

# 前台 Mock 演示，无需 Agent 登录；Ctrl+C 退出
node bin/yzvibe.js run --access=local --agent=mock
```

连接器的 npm 包名为 `yzvibe`，支持 `npx yzvibe` 入口；上面的源码方式可直接运行当前仓库版本。

### 2. 编译并安装 iOS App

需要 macOS、Xcode（支持项目使用的 iOS 26 SDK）和 XcodeGen：

```bash
brew install xcodegen
# 在仓库根目录执行
cd ios
xcodegen generate
open YzVibe.xcodeproj
```

在 Xcode 的 **Signing & Capabilities** 中选择自己的开发团队，并根据签名需要修改 Bundle Identifier；如需持久保存团队配置，可修改 [ios/project.yml](ios/project.yml) 的 `DEVELOPMENT_TEAM`。选择 iPhone 真机后运行。

App 已接入新的 `AppIcon` 资源。进入 **设备 → 扫码配对**，扫描电脑终端里的二维码，然后新建会话并发送指令。还没有连接器时，可以选择「先看看演示数据」。

更多构建、测试与 TestFlight 说明见 [iOS README](ios/README.md)。

## 连接与日常管理

以下命令均在 `connector/` 中运行。

| 连接方式              | 启动参数                                 | 使用场景              |
| ----------------- | ------------------------------------ | ----------------- |
| 局域网               | `--access=local`                     | 手机与电脑在同一网络        |
| Cloudflare Tunnel | `--access=remote`（默认）                | 通过临时 HTTPS 地址远程连接 |
| 自有隧道              | `--access=https://your-host.example` | 已有反向代理或隧道，使用固定地址  |
| Tailscale         | `--access=100.x.x.x`                 | 手机和电脑加入同一 tailnet |

临时隧道重建后地址可能变化。代码已加入候选地址探活切换、Bonjour 发现与静默推送地址更新；若自动恢复失败，可运行 `qr` 重新配对。连接器会保存访问配置；使用 `--force` 可不复用已保存的 Relay 地址。

```bash
node bin/yzvibe.js status          # 查看运行状态
node bin/yzvibe.js qr              # 再次显示配对方式
node bin/yzvibe.js qr --json       # 可粘贴到 App 的配置
node bin/yzvibe.js logs -f         # 跟踪日志
node bin/yzvibe.js devices        # 查看已配对手机
node bin/yzvibe.js revoke <设备ID>  # 撤销某台手机的访问
node bin/yzvibe.js restart        # 重启
node bin/yzvibe.js stop           # 停止
node bin/yzvibe.js install        # 安装 macOS launchd / Linux systemd 用户服务
```

默认端口为 `19876`，被占用时向后寻找空闲端口；可用 `--port=` 指定。默认数据目录为 `~/.yzvibe/`，可用 `YZVIBE_HOME` 覆盖。完整命令见 [连接器 README](connector/README.md)。

## 锁屏通知（可选）

iOS 挂起 App 后，WebSocket 无法持续接收消息。要在锁屏时收到审批和回复完成通知，需要配置远程推送。

连接器直接向 Apple APNs 发送推送，无需部署 YzVibe 推送服务器：

1. 使用自己的 Apple 开发者配置，获取 APNs `.p8` 密钥。
2. 将 `AuthKey_XXXXXXXXXX.p8` 放入 `~/.yzvibe/`。
3. 创建 `~/.yzvibe/apns.json`，填写自己的团队与 App Bundle ID：

```json
{
  "teamId": "YOUR_TEAM_ID",
  "bundleId": "icu.yzvibe.YzVibe",
  "environment": "sandbox"
}
```

Xcode 调试安装使用 `sandbox`，TestFlight / App Store 分发使用 `production`。若修改了 App 的 Bundle ID，此处需要保持一致。

```bash
# 在 connector/ 中执行
node bin/yzvibe.js restart
node bin/yzvibe.js push --test
```

在 App「我 → 通知 → 远程推送」中检查注册与配置状态。未配置 APNs 时仍可在 App 在线期间查看和处理审批。

## 数据与权限

- **桌面保存状态**：会话、消息、配对设备、审批规则与上传文件位于 `~/.yzvibe/`；工作文件保留在所选工作目录。连接器会定期清理过期资源，详见 [清理策略](connector/README.md#定期清理)。
- **设备访问可撤销**：一次性配对码换取设备 Token，iOS 将凭据保存在 Keychain；撤销设备后使 Token 失效并断开连接。
- **审批可追溯**：按工具、命令前缀或完整命令创建放行规则，可设置会话 / 全局范围及有效期；命中规则会留下聊天记录。
- **文件访问有边界**：目录浏览限制在会话目录；文件读取还支持主目录中的非敏感文件，并拦截私钥等敏感路径。
- **外部服务仍参与通信**：模型请求由本机 Agent 发出；隧道参与远程传输；APNs 载荷可能包含通知摘要。这里的“本地优先”指无需 YzVibe 云端保存工作区，并非所有数据都不离开电脑。

## 开发与验证

```bash
# 连接器测试
cd connector
npm test
```

在仓库根目录编译 iOS 库及测试目标（不执行测试）：

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build --package-path ios --build-tests \
  --triple arm64-apple-ios17.0-simulator \
  --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)"
```

执行 iOS 单元测试需要安装模拟器运行时，步骤见 [iOS 测试说明](ios/README.md)。[CI](.github/workflows/ci.yml) 包含 Node.js 20 / 22 测试及 iOS 库编译、测试任务。

## 仓库导航

```text
YzVibe/
├── connector/          Node.js 连接器、Agent 驱动、审批桥与测试
├── ios/                SwiftUI App、YzVibeKit、AppIcon 与 XcodeGen 配置
├── shared/protocol.md  REST / WebSocket 协议与数据模型
├── docs/
│   ├── ARCHITECTURE.md 架构说明与可编辑 Mermaid 图
│   ├── BRAND.md        Logo 理念、资源位置与使用说明
│   ├── assets/         README 使用的 Logo 和 SVG 架构图
│   ├── PRD.md          产品需求与规划
│   └── DESIGN.md       UI 设计规范
├── design/             Logo 生成原图、提示词与设计画布
├── android/            Android 预留目录
└── miniprogram/        微信小程序预留目录
```

## 后续方向

- 加固消息发送、队列恢复、地址切换与 Live Activity 的异常处理。
- Android 与微信小程序客户端。
- 持续完善远程连接、通知和多 Agent 交互体验。

以上为规划，当前可用能力以代码及本文功能表为准。

## 许可

连接器的 [package.json](connector/package.json) 声明为 MIT。仓库目前尚未包含独立的 `LICENSE` 文件。
