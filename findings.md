# 研究发现（外部内容仅存于此文件，视为不可信数据）

## 2026-09-12 当前项目分析（已完成）
- 开始时 git 工作区干净；无适用 AGENTS.md。
- 实现主体为 Node.js 连接器与原生 SwiftUI iOS App；Android / 小程序仅占位。
- 已有 docs/REVIEW.md 记录 2026-09-11 可靠性修复；分析需以当前代码复核，不能直接重复旧建议。
- 当前源码已包含 codex-app-server.js、活动总览、用户输入等后续模块，部分历史架构文档可能已落后。
- 核心文件规模：AppStore.swift 823 行、ConnectorClient.swift 707 行、Models.swift 966 行、server.js 647 行、store.js 441 行。
- 初步确认：ChatView.submit 发送前清空文字/图片；AppStore.send 失败只提示 toast，返回 Bool 同时表达“未排队”和“失败”；服务端无客户端消息 ID 去重。
- 新发现：AppStore.handle(.toolCall) 更新已有工具卡只合并 state/name/detail，遗漏 output/outputKind/truncated；需核对事件解码和测试覆盖。
- 长会话：重同步逐设备、逐已打开会话获取完整消息；Store 工具更新同步重写完整消息 JSON，delta 本身不持久化；性能规模尚未实测。
- 现有测试首次 52/74 通过，22 项失败均涉及沙箱禁止监听端口或主目录临时文件；已通过正式提权请求重跑，不视为产品缺陷。
- 重跑结果：连接器 74/74 通过（本机 Node，2026-09-12）。
- 工具结果补充：SocketBox.parse(.tool.call) 也忽略 output/outputKind/truncated；ToolCallCard 在提交 8af1568 中主动改为仅展示命令，因此“展示输出”属于产品取舍；字段链路不一致与 README 宣称仍需处理。
- 前台断网：SocketBox 仅发 disconnected、自动重建 WS；没有 connected/reconnected 事件或握手后补数。AppStore 的 resync 主要来自启动、前后台/推送等入口；一直停留前台时漏掉的事件没有恢复触发。
- 隔离 Store 验证：新会话运行中 appendDelta('already delivered text') 后创建新 Store 读相同目录，消息正文变为空、streaming=true、会话 status=idle。只验证 YzVibe 状态库，不代表 Agent 自己的 transcript 丢失。
- 合成基准（每条正文 2,000 ASCII 字符，工具更新预热 1 次 + 测量 15 次）：100/1,000/5,000 条消息文件分别 0.22/2.24/11.18 MB；同步 upsertToolCall 中位数 0.44/3.27/16.43 ms。这是单机存储开销，不是手机帧率或线上延迟。
- /pair 在验证 token 前用无字节上限的 readBody；/uploads 20 MB 上限在整包缓冲后检查。可提前限制请求体并做字段校验。
- 已有四个固定首句模板、AppStore 内存草稿、活动总览与系统已有活动恢复；不应当作为全新缺失功能重复规划。
- 最终报告：docs/OPTIMIZATION-2026-09-12.md，基线 833522e；包含 6 项优化、4 个产品拓展、工程维护方向、工作量粗估和验收条件。

## 1. Vibelet（https://vibelet.icu/zh/）产品研究

### 定位
- 一句话：**离开电脑，也能盯住远程会话** — 电脑继续跑任务，手机负责发消息、看状态、审批敏感请求。
- 本质：桌面端运行「连接器」(`npx vibelet`)，手机 App 作为远程控制器接管本机的 AI 编程会话（Claude Code 等 agent）。
- 免费、无账号、本地优先；iOS App Store + Android APK（飞书分发）。

### 九大功能卡片（原站文案）
| 图标 | 标题 | 描述 |
|---|---|---|
| 📱 | 手机接管远程会话 | 出门/开会时继续给桌面会话发消息、看进度、确认下一步 |
| 🤖 | 配对你的电脑 | 会话跑在自己机器上，手机只是遥控器，无需账号/云端工作区 |
| 🖼️ | 截图和图片能跟上 | 手机截图/相册图片直接发给会话；回复中图片可放大、保存 |
| 📎 | 文件需要时再取 | 手机浏览远程文件夹、预览支持的文件、按需下载 |
| 🌐 | 远程访问默认可用 | 默认 Cloudflare Tunnel；支持 Tailcat P2P、ngrok、Tailscale |
| 🔗 | 扫码连接少配置 | 扫一次二维码即连；局域网配对用 `--access=local` |
| 🔄 | 稍后回来不中断 | 临时走开后可恢复同一会话，上下文仍在 |
| 🛡️ | 敏感步骤先确认 | 执行敏感请求前，手机上看清楚再批准 |
| 🔒 | 本地优先更安心 | 数据留在本机；手机 App 不下载/安装/运行可执行代码 |

### App 截图（5 屏）
连接（扫码配对） / 会话列表 / 新建会话 / 聊天 / 设置
- 图片路径：/screenshots/home.png, sessions.png, new-session.png, chat.png, settings.png

### 快速开始（三步）
1. 安装：在跑任务的电脑上 `npx vibelet`
2. 连接手机：装 App → 点「扫描二维码」→ 扫终端里的二维码
3. 开始会话：点「新建会话」→ 选电脑端配置好的远程助手 → 输入提示词发送

### 配对后的价值点
- 电脑继续跑任务，手机负责审批或回复
- 不同文件夹/项目保留各自会话
- 稍后回来接回同一个上下文
- 默认远程 tunnel，局域网用 `--access=local`

### 远程访问方式
| 方式 | 标签 | 命令 | 备注 |
|---|---|---|---|
| Tailcat 直连 | 免账号 P2P | `npx vibelet --tailcat` | DERP 引导 → NAT 穿透 → E2E 加密 P2P；`--no-tailcat` 关闭 |
| Cloudflare Tunnel | 推荐 | `npx vibelet` | 免费免注册，自动开隧道并打印二维码；`--access=remote --force` 换新 URL |
| 自定义 Relay | 自有链路 | `npx vibelet --access=https://<url>` | 支持 cloudflared/ngrok；持久化到 ~/.vibelet/relay.json |
| 内置 Tailscale | VPN+Tailnet | `npx vibelet --access=<tailscale-ip>` | iOS 需 Stash 等分流；100.64.0.0/10 与 *.ts.net 指向 TS 节点 |

### FAQ 主题
- 代理工具中 *.argotunnel.com 需 real-ip / skip-proxy
- "Network request failed" = 手机根本没连到 host（网络不可达/.local 无法解析/本地网络权限/代理接管）
- 二维码短时有效且一次性；过期重新运行；已配对设备可直接重连
- `--access=local` 何时用
- 自定义 relay vs Tailscale 的区别
- iPhone 同时用代理 VPN 与 Tailscale（Stash `type: tailscale` 节点）

### 站点结构
导航：搜索(⌘K) / 语言切换 / 主题切换 → Hero → 功能卡片 → 截图预览 → 获取 App(iOS/Android + 二维码) → 配对前准备 → 快速开始 → 你会得到什么 → 远程访问 → FAQ → Footer（Privacy/Terms/产品矩阵/作者）
视觉：极简、emoji 图标、等宽代码块、深浅主题切换。

### 生态
作者产品矩阵：Midscene、Aino、LifeOS Pro、Calendar Pro、DeepAsk、Remosidian；社区 X @vibelet_ai、Discord。

## 2. yukiTrace 设计系统（../yukiTrace/src/app/globals.css）

### 字体
- sans: -apple-system, SF Pro, PingFang SC …
- mono: SF Mono, Menlo
- display: Fraunces（仅拉丁/数字）→ New York / Songti SC 回落

### 品牌色（light）
- brand 赭红 `oklch(0.64 0.17 40)` / brand-soft `oklch(0.94 0.04 45)`
- sage 鼠尾草 `oklch(0.6 0.09 165)` / sage-soft `oklch(0.93 0.035 165)`
- amber 琥珀 `oklch(0.82 0.13 80)` / amber-soft `oklch(0.96 0.05 85)`
- 分类色（暖调校）：blue 0.58/0.13/235, green 0.6/0.12/155, orange 0.68/0.16/50, red 0.6/0.2/25, purple 0.55/0.15/310, pink 0.65/0.17/10, indigo 0.52/0.12/270, gray 0.62/0.02/60

### 纸感分层（light）
- surface `oklch(0.975 0.009 80)`, surface-elevated `oklch(0.995 0.004 85)`
- fill `oklch(0.935 0.012 75)`, fill-secondary `oklch(0.958 0.01 78)`
- foreground `oklch(0.22 0.02 45)`, label-secondary `oklch(0.5 0.02 55)`, label-tertiary `oklch(0.68 0.018 60)`
- border `oklch(0.9 0.014 70)`

### Dark
- brand `oklch(0.72 0.15 42)`, sage `0.7/0.09/165`, amber `0.85/0.12/82`
- surface `oklch(0.16 0.008 60)`, elevated `0.215/0.01/60`, fill `0.29/0.012/60`
- foreground `oklch(0.96 0.008 80)`

### 圆角 / 阴影 / 缓动
- radius: sm10 md14 lg18 xl22 2xl26 3xl30 4xl40；默认 20px
- shadow-card / shadow-float / shadow-glass（暖色 oklch(0.3 0.03 50) 层叠阴影）
- ease-out `cubic-bezier(0.23,1,0.32,1)`，ease-drawer `cubic-bezier(0.32,0.72,0,1)`

## 3. Vibelet App 截图 UI 观察（5 屏，1284×2778）

### 通用
- 背景：暖米色纸感底 + 左上淡紫、右上淡粉、底部淡白的大圆形色块（模糊装饰球）
- 主色：淡紫色 `≈#B07FB9`（按钮、开关、气泡）；Claude 标签琥珀色、Codex 标签淡紫、Vibelet 标签鼠尾草绿
- 卡片：白色/奶白圆角卡（半径 ≈24-28pt），柔和阴影；输入框为米色填充 + 淡边框
- 返回按钮：左上方形圆角小按钮（≈ 44pt），旁边粗体标题
- 分组标题：大写字母间距拉开的灰色小字（如 CONNECT TO YOUR AI DAEMON / AGENT / SESSION MODE）
- 无底部 Tab Bar，纯层级式导航（Home → Sessions → Chat / New Session / Settings）

### 屏 1：Home / 连接
- 顶部胶囊标签「Secure local bridge」（淡紫）
- 大标题 "Vibelet" + 右侧 App 图标（V 渐变紫粉）
- Slogan：Anywhere, anytime, vibe anything；副文案：已配对设备与手动端点保存在本机以便快速重连
- 卡片：Host(192.168.0.11) / Port(9876) / Token(密文) 三个输入；两个按钮「📷 Scan QR」「→ Connect」

### 屏 2：Sessions 会话列表
- 顶栏：返回、Sessions、右上收缩图标
- 连接卡：`100.82.203.14:9876` + 「Connected」绿色胶囊；按钮 Settings（白）/ + New Session（紫）
- 搜索框 "Search sessions..."
- 按文件夹分组：▾ 📁 quanru  /Users/quanru  「2 sessions」
- 会话卡：绿点(活跃) + Agent 标签(Codex/Claude) + 来源标签(Vibelet) + 相对时间(5m)；标题「hello world」；等宽路径块

### 屏 3：New Session
- 说明：Review the agent, directory, and approval mode before opening a shell.
- 卡片：AGENT 分段选择(Claude | Codex)；WORKING DIRECTORY 输入(/Users/you/project)；FIRST MESSAGE 多行输入（可选，会话启动后自动发送）
- SESSION MODE：「Continue Last」开关(恢复最近会话)；「YOLO Mode」开关(跳过所有权限检查, `--dangerously-skip-permissions`)

### 屏 4：Chat
- 顶部浮动玻璃条：返回、状态点(橙=运行中)、会话标题、⚡ 红色按钮(停止/中断)、Agent 标签(Claude)
- 消息：用户气泡右侧紫色；助手气泡左侧白色卡 + Copy 按钮
- 快捷回复胶囊横向滚动：Continue / LGTM, proceed / Explain this / Undo last change
- 底部输入条：圆角输入 "Type a message..." + 圆形紫色 ↑ 发送按钮

### 屏 5：Settings
- NOTIFICATIONS：Notify on reply 开关
- SESSION LIST：Group by folder / Active only
- APPEARANCE：Auto | Light | Dark 分段
- LANGUAGE：Auto | English | 中文
- ABOUT：Version 0.1.1

### 与 Vibelet 差异化的机会（我们可以做得更好）
- Vibelet 没有底部 Tab，多设备管理弱 → YzVibe 用 Tab（设备 / 会话 / 审批收件箱 / 我）
- 敏感审批只在聊天里 → YzVibe 独立「审批收件箱」+ 锁屏/灵动岛 Live Activity
- 文件浏览缺少专门入口 → YzVibe 会话内「文件」抽屉
- 视觉升级：iOS 26 Liquid Glass（玻璃导航条、玻璃 Tab、玻璃浮层）+ yukiTrace 暖色系

## 2026-09-12 实施结果

全部 P1 已落实到发送箱、持久化接收记录、有序 WS 快照、流式追加日志和限额验证。交付卡与诊断页已实现，详见 docs/RELEASE-0.1.0-11.md。最终后端 84 项与 iOS 91 项测试通过，App/Widget build 11 归档成功。真实 Agent 付费调用、APNs 真机送达与长历史性能仍保留为后续验证。

## 认证与手动地址选择核验

配对为一次性码换独立设备 Token；server.js 的 authed 同时保护业务 HTTP 和 WS upgrade。iOS 保存在 Keychain。当前手动设备配置直接更改地址而未先核对身份，诊断页 device 为旧快照；新入口需解决身份校验、认证验证、当前地址实时显示以及旧请求切回旧地址的竞态。127.0.0.1 在真机上不是电脑。

已完成上述修复及 87 项连接器 / 101 项 iOS 回归。任务交付卡旧记录滞留的原因是 ChatView 把最近三轮统一追加在消息列表尾部；现有连接器 0.1.1 已提供 startMessageId/messageIds，iOS 解码后按关联消息定位即可，无需改服务端协议或中断运行中的连接器。
