# YzVibe 产品需求文档（PRD）

> 版本 0.1 · 2026-09-09 · 参考对象：Vibelet（vibelet.icu）
> 多端共用：本文档是 iOS / Android / 小程序 三端的唯一需求来源。

## 1. 一句话定位

**离开电脑，AI 会话照样往前推。**
电脑上跑着 Claude Code / Codex 等编程 Agent，YzVibe 把手机变成它的遥控器：发消息、看进度、审批敏感操作、取文件。会话始终跑在你自己的机器上，手机不存代码、不跑代码。

## 2. 目标用户与场景

| 用户 | 场景 | 痛点 |
|---|---|---|
| 独立开发者 | 让 Agent 跑一个 20 分钟的重构，自己去接孩子 | 必须守在电脑前点「允许」 |
| 团队 Tech Lead | 开会时 Agent 问「是否允许 rm -rf dist」 | 来不及回到座位，任务卡死 |
| 多机器用户 | 家里 Mac mini + 公司 MacBook 各跑几个项目 | 切换设备、切换项目成本高 |
| 非技术协作者 | 产品经理想让 Agent 改一段文案并看结果截图 | 不会开终端 |

核心 JTBD：**当我不在电脑前，我需要在 30 秒内知道 Agent 卡在哪、并一键让它继续。**

## 3. 产品原则

1. **本地优先**：无账号、无云端工作区，数据留在用户机器。
2. **审批是第一公民**：敏感操作的批准/拒绝要比发消息更快触达。
3. **一次扫码**：配对成本 ≤ 10 秒；重连零成本。
4. **手机不执行代码**：App 只展示、只转发，不下载/安装/运行可执行内容。
5. **多设备多项目**：设备 → 项目文件夹 → 会话 三级模型。

## 4. 功能矩阵（MoSCoW）

### Must（v1.0）
| 模块 | 功能 | 说明 |
|---|---|---|
| 配对 | 扫码配对 | 扫描桌面连接器终端二维码；二维码短时有效、一次性 |
| 配对 | 手动端点 | Host / Port / Token 手输；支持 LAN IP、Tailscale IP、https relay |
| 配对 | 设备列表 | 已配对设备持久化在手机；显示在线状态、连接方式（Tunnel / LAN / P2P / Tailscale） |
| 会话 | 会话列表 | 按文件夹分组、仅显示活跃、搜索；卡片显示 Agent 标签 / 状态点 / 相对时间 / 路径 |
| 会话 | 新建会话 | 选 Agent（Claude / Codex / 自定义）、工作目录、首条消息、Continue Last、YOLO 模式 |
| 会话 | 恢复会话 | 离开后回来接回同一上下文 |
| 聊天 | 消息流 | 用户 / 助手气泡、Markdown、代码块、工具调用折叠卡、流式输出 |
| 聊天 | 快捷回复 | Continue / LGTM / Explain / Undo 等胶囊，可自定义 |
| 聊天 | 中断 | 一键 Stop 当前轮 |
| 聊天 | 图片 | 发送截图/相册图片；回复中的图片放大、保存 |
| 审批 | 审批卡 | 敏感请求（shell 命令、文件写入、网络访问）以卡片呈现：完整命令、影响范围、Allow / Deny / Allow once |
| 审批 | 审批收件箱 | 跨设备、跨会话的待审批汇总；角标计数 |
| 审批 | 推送 | 有待审批 / 回复完成时本地或远程推送 |
| 文件 | 远程文件浏览 | 浏览工作目录、预览文本/图片/Markdown、按需下载 |
| 设置 | 通知 / 列表偏好 / 外观 / 语言 / 关于 | |

### Should（v1.1）
- Live Activity + 灵动岛：显示当前会话状态与待审批数
- 审批规则：记住「本会话总是允许 npm test」
- 会话 Diff 视图：查看 Agent 改动的文件差异
- 多 Agent 并排（同一目录多个会话切换）

### Could（v1.2+）
- Apple Watch 审批
- 语音输入
- 小组件：最近会话 / 待审批
- 会话分享（只读链接）

### Won't（明确不做）
- 云端账号系统、云端存储会话
- 手机端执行代码 / 终端模拟器
- 计费系统（v1 免费）

## 5. 信息架构

```
YzVibe
├─ Tab 1 设备 Devices
│   ├─ 设备卡（在线/离线，连接方式，会话数）
│   ├─ 扫码配对（全屏相机 + 玻璃取景框）
│   └─ 手动添加端点（Host/Port/Token 表单）
├─ Tab 2 会话 Sessions
│   ├─ 设备切换器（顶部胶囊）
│   ├─ 搜索 / 过滤（活跃 / 全部）
│   ├─ 按文件夹分组列表
│   ├─ 新建会话（Sheet）
│   └─ 会话详情 Chat
│       ├─ 消息流
│       ├─ 内嵌审批卡
│       ├─ 快捷回复
│       ├─ 输入条（文本 / 图片 / 中断）
│       └─ 文件抽屉（右滑 / 顶栏按钮）
├─ Tab 3 审批 Approvals
│   ├─ 待处理（按时间）
│   └─ 历史
└─ Tab 4 我 Me
    ├─ 通知
    ├─ 会话列表偏好
    ├─ 外观（自动/浅/深）
    ├─ 语言
    ├─ 安全（Face ID 解锁审批）
    └─ 关于
```

## 6. 关键流程

### 6.1 首次配对
1. 电脑运行 `npx yzvibe`（默认 Cloudflare Tunnel，打印二维码）
2. 手机打开 App → 设备 Tab 空态「扫码配对」→ 扫码
3. App 解析 `yzvibe://pair?host=…&port=…&token=…&mode=tunnel` → 握手 `/health`
4. 成功：设备卡入列，自动跳到会话 Tab

### 6.2 审批
1. Agent 触发敏感请求 → 连接器推送 `approval.requested`
2. 手机推送横幅（含命令摘要）→ 点击进入审批卡
3. Allow / Deny / Allow once（可选 Face ID）→ 连接器回传 → Agent 继续
4. 审批结果在聊天流中以折叠卡留痕

### 6.3 恢复会话
- 打开 App → 上次会话 Tab 状态自动恢复；WebSocket 重连后拉取增量消息

## 7. 连接方式（沿用 Vibelet 能力面）

| 方式 | 默认 | 手机需要 | 命令 |
|---|---|---|---|
| Cloudflare Tunnel | ✅ | 无 | `npx yzvibe` |
| 局域网 | | 同一 Wi-Fi | `npx yzvibe --access=local` |
| P2P 直连 | | 无 | `npx yzvibe --p2p` |
| 自定义 Relay | | 无 | `npx yzvibe --access=https://<url>` |
| Tailscale | | 加入同一 tailnet | `npx yzvibe --access=<tailscale-ip>` |

## 8. 技术方案草案

### 8.1 架构
```
┌──────────────┐  WebSocket/HTTPS  ┌──────────────┐   stdio/PTY   ┌─────────────┐
│ 手机 App     │ ◄──────────────► │ 桌面连接器    │ ◄───────────► │ Claude Code │
│ iOS/Android/ │  (tunnel/LAN/P2P) │ npx yzvibe   │               │ Codex …     │
│ 小程序       │                   │ Node.js      │               └─────────────┘
└──────────────┘                   └──────────────┘
```
- 连接器：Node.js CLI，负责启动 Agent 进程、解析输出为结构化事件、暴露 REST + WS、管理隧道
- 手机端：纯客户端，Token 存 Keychain / 安全存储

### 8.2 协议（详见 shared/protocol.md）
- REST：`GET /health`、`GET /sessions`、`POST /sessions`、`GET /files?path=`、`GET /files/download`
- WS 事件：`session.created` `message.delta` `message.done` `tool.call` `approval.requested` `approval.resolved` `session.status`
- 客户端命令：`message.send` `session.stop` `approval.respond` `session.resume`

### 8.3 各端技术栈
| 端 | 栈 | 备注 |
|---|---|---|
| iOS | SwiftUI, iOS 17+，iOS 26 启用 Liquid Glass | 目录 ios/ |
| Android | Kotlin + Jetpack Compose，Material 3 Expressive 上模拟玻璃 | 目录 android/ |
| 小程序 | 微信小程序（Skyline）或 uni-app | 目录 miniprogram/ |
| 连接器 | Node.js + TypeScript | 后续 connector/ |

## 9. 非功能需求
- 冷启动 ≤ 1.5s；消息延迟 ≤ 300ms（LAN）
- 断线自动重连（指数退避，≤ 30s）
- 无障碍：Dynamic Type、VoiceOver 标签、对比度 ≥ 4.5:1
- 隐私：不采集会话内容；仅本地日志

## 10. 里程碑
| 里程碑 | 内容 | 目标 |
|---|---|---|
| M0 | 规划 + 设计稿（本次） | 2026-09 |
| M1 | iOS 静态 UI + Mock 数据 | 2026-09 |
| M2 | 连接器 MVP + iOS 真实联调 | 2026-10 |
| M3 | 审批推送 + Live Activity | 2026-11 |
| M4 | Android / 小程序 | 2026-12 |
