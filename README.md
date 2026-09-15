<p align="center">
  <img src="docs/assets/yzvibe-logo.png" width="112" height="112" alt="柚子Vibe Logo：白底小柚子女孩抱着橙色 V" />
</p>
<h1 align="center">柚子Vibe</h1>
<p align="center"><strong>离开电脑，继续 Vibe。</strong></p>
<p align="center">在 iPhone 上继续电脑里的 AI 编程会话：发指令、看输出、批操作、取文件。</p>
<p align="center">
  <a href="https://vibe.aiyuki.cc/">产品介绍</a> ·
  <a href="#快速开始">快速开始</a> ·
  <a href="#系统架构">系统架构</a> ·
  <a href="docs/ARCHITECTURE.md">架构详解</a> ·
  <a href="docs/BRAND.md">Logo 与 iOS 图标</a> ·
  <a href="shared/protocol.md">通信协议</a>
</p>

***

柚子Vibe（YzVibe）是一个本地优先的 AI 编程遥控器。桌面连接器在你的电脑上运行 Claude Code、Codex 或 OMP，iOS App 负责交互和展示。你可以在手机上新建会话，也可以打开连接器发现的终端历史会话，接着往下聊。

**无需柚子Vibe 账号或自建云端工作区。** 会话记录保存在电脑上，手机不执行代码。Agent 仍通过各自配置的模型服务工作；远程连接可经过隧道，锁屏通知使用 Apple APNs。

## 能做什么

| 能力     | 当前实现                                               |
| ------ | -------------------------------------------------- |
| 随时续聊 | 多设备、多会话、终端历史恢复；选择 Agent、目录、模式和模型，通过分档滑条调整思考力度 |
| 说出想法、听回复 | 按住说话、上滑取消，Apple 端侧识别后编辑再发送；iOS 原生朗读回复正文，过滤代码、常见命令和日志 |
| 阅读与复制 | 原生文本选区，连续正文支持跨段落复制；回复一键复制，图片、表格、代码块独立排版 |
| 看清执行过程 | 对话更新、工具状态、交付详情中的真实输出、文件改动 diff、用量与额度信息                 |
| 手机上审批  | Claude / Codex / OMP 权限请求进入聊天卡片和审批收件箱；支持拒绝理由、Face ID 确认和可撤销的放行规则 |
| 附件与快捷工具 | 星光菜单统一照片、拍摄、文件、命令行与技能入口；每条最多 6 个附件、总计 20 MB；远程文件预览和下载 |
| 离线后接上 | 可靠待发送箱、断线补齐与候选地址切换；区分重连、地址失效和凭据失效，支持局域网找回 |
| 少打扰的通知 | 按设备同步审批与完成通知偏好；只在最终回复时通知，支持锁屏与 Live Activity（需配置 APNs） |
| 日常常驻   | 后台守护、日志轮转、设备撤销、资源清理、macOS / Linux 用户服务             |

**当前版本**：Connector **[0.1.3](https://www.npmjs.com/package/yzvibe)** 已发布到 npm，直接运行 `npx yzvibe@latest start`，无需拉取源码。iOS 最新构建为 **[0.1.0 (35)](docs/RELEASE-0.1.0-35.md)**，2026-09-15 已确认进入 TestFlight 内部测试，包含会话列表、聊天阅读与大字号排版优化。本仓库未提供公开邀请链接，非内部测试成员可从源码构建。

**最近更新**：

- **OMP 接入**：与 Claude Code、Codex 并列，支持会话恢复、消息队列、工具审批和用量展示。接入能力与限制见 [OMP 说明](docs/OMP.md)。
- **手机配置 OMP 模型**：只显示电脑端明确配置的模型；通过 HTTPS 保存 Base URL、Key、Model Name 到终端配置。下一轮消息生效，独立终端需重开 OMP；不后台轮询、不调用模型验证。
- **回复文件直接查看**：本地 Markdown 默认渲染，支持相对链接和图片；图片可全屏缩放，视频下载后播放，外链继续交给浏览器。详见 [文件预览](docs/REMOTE-FILE-PREVIEW.md) 和 [build 25](docs/RELEASE-0.1.0-25.md)。
- **会话品牌图标**：名称前显示 Codex、Claude、OMP 的随 App 打包的原彩高清 PNG Logo，保留状态指示与运行动画。
- **输入与阅读**：统一附件/命令/技能菜单、带触感的思考力度滑条、原生文本选区、复制、按住说话及正文朗读。

iOS 客户端为 **SwiftUI / iOS 17+**，iOS 26 使用 Liquid Glass，低版本使用材质模糊。Android 原生首版已可构建（Android 10+），支持配对、会话、聊天、审批、文件和语音入口；仍需厂商后台推送和真机验收，详见 [Android 构建与兼容说明](android/README.md)。微信小程序仅预留目录。

### Claude Code、Codex 与 OMP 的区别

以下是本仓库驱动的行为，具体映射见 [Claude 选项](connector/src/agents/options.js) 、[Codex App Server 驱动](connector/src/agents/codex-app-server.js) 与 [OMP 策略](connector/src/agents/omp-policy.js)。

| 会话模式 | Claude Code | Codex | OMP |
| ------ | ---------------- | ------------------------ | ---- |
| Plan | 原生规划模式，通过权限桥处理请求 | 只读沙箱 + 规划提示词 | 仅本地读取与搜索 |
| Normal | 敏感操作发到手机审批 | 工作目录可写沙箱；额外权限请求发到手机审批 | 本地读取自动允许，其他工具手机审批 |
| Trust | 跳过权限检查 | 跳过审批和沙箱 | 跳过工具审批 |

OMP 使用工具拦截，不提供操作系统沙箱；不应在手机和独立终端同时写入同一 OMP 会话。

Trust 会允许 Agent 直接执行操作，请在了解其含义后选择。Mock 驱动用于演示与开发，不调用真实模型。

## 系统架构

![柚子Vibe 架构：iPhone 端侧语音与交互、桌面连接器、Claude / Codex / OMP 驱动及可选 APNs](docs/assets/architecture.svg)

1. **配对**：电脑生成一次性配对码，手机扫码、打开配对链接或粘贴 JSON，换取设备 Token。
2. **执行**：手机通过 REST 发指令，连接器在指定工作目录启动本地 Agent；输出经 WebSocket 返回。
3. **审批**：Claude 经 MCP 审批桥、Codex 经 App Server 权限回调、OMP 经私有工具审批扩展提出请求；连接器匹配放行规则，或等待手机决定。
4. **恢复**：手机通过磁盘待发送箱与连接器接收对账恢复投递，重连补齐消息；工具输出按需读取，交付卡关联所属轮次。
5. **语音与通知**：语音在 iPhone 端侧转写为可编辑草稿，发送后按普通文本处理；回复由 iOS 原生朗读。连接器直接向 APNs 发送审批、最终回复和 Live Activity 更新。

组件职责、审批时序和数据边界见 [架构详解](docs/ARCHITECTURE.md)。

## 快速开始

### 1. 在电脑上启动连接器

需要 **Node.js 20+**。先在电脑安装并登录对应的 `claude`、`codex` 或 `omp`，确认能在目标目录运行。

```bash
npx yzvibe@latest start
```

默认启动后台连接器并展示配对二维码，终端可关闭。推荐预先安装 `cloudflared`（macOS：`brew install cloudflared`）；连接器也会尝试通过 npx 启动它，失败时退回局域网。

```bash
npx yzvibe@latest start --access=local   # 同一网络直连
npx yzvibe@latest start --agent=omp      # 默认 OMP
npx yzvibe@latest status                # 查看版本与运行状态
```

### 升级连接器

普通 npx 后台实例，等正在运行的任务结束后执行：

```bash
npx yzvibe@latest restart
```

这会使用 npm 最新版重启；只运行 `start` 不会替换已有进程。会话与配对数据保留在 `~/.yzvibe`，重启会中断进行中的任务，临时隧道地址可能变化。

如果使用全局安装：

```bash
npm install -g yzvibe@latest
yzvibe restart
```

**开机自启实例**使用服务文件记录的路径。建议全局安装；从源码或 npx 迁移、Node 安装路径变化时，需要用新版全局命令重新执行 `yzvibe install`，并带上原先的 `--access`、`--port` 等参数。单纯执行 npx restart 不会改写旧服务的入口路径。

源码开发仍可在仓库中运行：

```bash
cd connector
npm install
npm start
```

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

## OMP 模型与文件预览

在「我 → 模型列表 → OMP」查看当前电脑明确配置的模型，也可通过 HTTPS 添加 OpenAI 兼容模型，填写 Base URL、API Key 和 Model Name。Key 不回显，留空保留旧值；更改接口地址需重新填写 Key。同供应商模型共享地址与密钥。保存不调用模型验证，不改变终端默认模型；手机下一轮消息重建进程并恢复原会话，独立终端需重新打开 OMP。详细能力、配置冲突处理与限制见 [OMP 接入](docs/OMP.md)。

点击回复中的本地文件路径即可在 App 内查看：Markdown 默认渲染且可切换源码，相对链接按文档目录解析；图片可全屏缩放，视频下载到临时文件后播放。HTTP/HTTPS 外链仍在浏览器打开。文件需仍存在于会话所属电脑；Markdown/代码内嵌预览上限 2 MB，更大的文档可下载。详见 [远程文件预览](docs/REMOTE-FILE-PREVIEW.md)。

## 手机上的输入与阅读

- **按住说话**：按住输入栏的「语音」，上滑取消、滑回继续；松手后将转写保留为草稿，确认或修改后再发送。取消只撤销本段转写，保留原有草稿。首次使用需允许麦克风和语音识别；不支持端侧识别的设备或语言不会改走云端识别。
- **听回复、复制正文**：回复底部可朗读或复制；朗读会过滤代码块、常见命令和日志，可停止或切换回复。录音与朗读互斥。正文支持原生拖动选区，连续正文可跨段落选择。
- **统一工具入口**：星光菜单提供照片、拍摄、文件、命令行和技能。思考力度通过分档滑条调整，切档有触感反馈，松手保存；实际参数仍由所选 Agent / 模型驱动处理。
- **审批与 Trust**：可为当前命令建立有范围、期限的放行规则，也可将当前会话切换为 Trust。Trust 跳过权限检查（Codex 同时跳过沙箱），与仅放行一条规则的范围不同。

## 连接与日常管理

以下命令可在任意目录运行。开机自启建议使用全局安装的 `yzvibe install`。

| 连接方式              | 启动参数                                 | 使用场景              |
| ----------------- | ------------------------------------ | ----------------- |
| 局域网               | `--access=local`                     | 手机与电脑在同一网络        |
| Cloudflare Tunnel | `--access=remote`（默认）                | 通过临时 HTTPS 地址远程连接 |
| 自有隧道              | `--access=https://your-host.example` | 已有反向代理或隧道，使用固定地址  |
| Tailscale         | `--access=100.x.x.x`                 | 手机和电脑加入同一 tailnet |

默认远程模式无需传 `--access`。自有 HTTPS 地址仅设置连接器公布的入口，需自行运行隧道或反向代理，并将源站指向连接器端口。

临时隧道重建后地址可能变化。代码已加入候选地址探活切换、Bonjour 发现与静默推送地址更新；若自动恢复失败，可运行 `qr` 重新配对。连接器会保存访问配置；使用 `--force` 可不复用已保存的 Relay 地址。

```bash
npx yzvibe@latest status          # 查看运行状态
npx yzvibe@latest qr              # 再次显示配对方式
npx yzvibe@latest qr --json       # 可粘贴到 App 的配置
npx yzvibe@latest logs -f         # 跟踪日志
npx yzvibe@latest devices        # 查看已配对手机
npx yzvibe@latest revoke <设备ID>  # 撤销某台手机的访问
npx yzvibe@latest restart        # 重启
npx yzvibe@latest stop           # 停止
yzvibe install                    # 全局安装后注册开机自启
```

默认端口为 `19876`，被占用时向后寻找空闲端口；可用 `--port=` 指定。默认数据目录为 `~/.yzvibe/`，可用 `YZVIBE_HOME` 覆盖。完整命令见 [连接器 README](connector/README.md)。

## 锁屏通知（可选）

iOS 挂起 App 后，WebSocket 无法持续接收消息。要在锁屏时收到审批和回复完成通知，需要配置远程推送。

连接器直接向 Apple APNs 发送推送，无需部署柚子Vibe推送服务器：

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
# 在电脑终端执行
npx yzvibe@latest restart
npx yzvibe@latest push --test
```

在 App「我 → 通知 → 远程推送」中检查注册与配置状态。审批与回复完成的开关会按设备同步到连接器；完成通知只在最终回复时发送，避免中间工具轮次重复打扰。未配置 APNs 时仍可在 App 在线期间查看和处理审批。

## 数据与权限

- **桌面保存状态**：会话、消息、配对设备、审批规则与上传文件位于 `~/.yzvibe/`；工作文件保留在所选工作目录。连接器会定期清理过期资源，详见 [清理策略](connector/README.md#定期清理)。
- **设备访问可撤销**：一次性配对码换取设备 Token，iOS 将凭据保存在 Keychain；撤销设备后使 Token 失效并断开连接。
- **审批可追溯**：按工具、命令前缀或完整命令创建放行规则，可设置会话 / 全局范围及有效期；命中规则会留下聊天记录。
- **文件访问有边界**：目录浏览限制在会话目录；文件读取还支持主目录中的非敏感文件，并拦截私钥等敏感路径。
- **外部服务仍参与通信**：模型请求由本机 Agent 发出；隧道参与远程传输；APNs 载荷可能包含通知摘要。这里的“本地优先”指无需柚子Vibe 云端保存工作区，并非所有数据都不离开电脑。

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
├── html/               静态产品介绍页、打包脚本与 nginx 配置
├── shared/protocol.md  REST / WebSocket 协议与数据模型
├── docs/
│   ├── ARCHITECTURE.md 架构说明与可编辑 Mermaid 图
│   ├── BRAND.md        Logo 理念、资源位置与使用说明
│   ├── assets/         README 使用的 Logo 和 SVG 架构图
│   ├── PRD.md          产品需求与规划
│   └── DESIGN.md       UI 设计规范
├── design/             Logo 生成原图、提示词与设计画布
├── android/            Kotlin / Compose Android 客户端
└── miniprogram/        微信小程序预留目录
```

## 后续方向

- 加固消息发送、队列恢复、地址切换与 Live Activity 的异常处理。
- Android 厂商后台推送、真机兼容性与完整体验对齐；微信小程序客户端。
- 持续完善远程连接、通知和多 Agent 交互体验。

以上为规划，当前可用能力以代码及本文功能表为准。

## 许可

连接器的 [package.json](connector/package.json) 声明为 MIT。仓库目前尚未包含独立的 `LICENSE` 文件。
