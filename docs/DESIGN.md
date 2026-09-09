# YzVibe 设计规范（多端共用）

> 风格：Apple iOS 26 Liquid Glass（液态玻璃） × yukiTrace 暖调纸感配色
> 本文是 iOS / Android / 小程序三端的视觉唯一来源；各端把 token 映射到自己的原生系统。

## 1. 设计立场

- **玻璃只用于「漂浮层」**：导航条、Tab 栏、浮动输入条、审批卡、Toast。内容层永远是不透明的纸感卡片，保证可读性。
- **暖而不腻**：底色是偏暖的米色纸（oklch 0.975 / hue 80），不是纯白；主色是赭红，克制使用，只给主按钮、选中态、状态强调。
- **三种强调色各司其职**：赭红 = 行动 / 用户消息；鼠尾草 = 在线 / 成功 / 已批准；琥珀 = Claude 标签 / 等待中 / 警示。
- **背景装饰球**：三个巨大的柔焦圆（brand-soft、sage-soft、amber-soft）固定在页面角落，玻璃层折射它们才有「液态」感。
- **圆角大、阴影暖**：卡片 22-26pt，胶囊全圆，阴影用暖棕色而非纯黑。

## 2. 颜色 Token

### 2.1 品牌与语义色

| Token | Light | Dark | 用途 |
|---|---|---|---|
| `brand` | `oklch(0.64 0.17 40)` ≈ #C2573A | `oklch(0.72 0.15 42)` ≈ #E07A5A | 主按钮、用户气泡、选中态、链接 |
| `brand-soft` | `oklch(0.94 0.04 45)` ≈ #F7E3DA | `oklch(0.30 0.06 40)` | 主色淡底、胶囊标签底 |
| `sage` | `oklch(0.60 0.09 165)` ≈ #4E9A7E | `oklch(0.70 0.09 165)` | 在线、Connected、Allowed |
| `sage-soft` | `oklch(0.93 0.035 165)` ≈ #DFF0E8 | `oklch(0.28 0.04 165)` | 绿色胶囊底 |
| `amber` | `oklch(0.82 0.13 80)` ≈ #E6B54A | `oklch(0.85 0.12 82)` | Claude 标签、运行中状态点、等待审批 |
| `amber-soft` | `oklch(0.96 0.05 85)` ≈ #FBF0D2 | `oklch(0.30 0.05 80)` | 琥珀胶囊底 |
| `danger` | `oklch(0.60 0.20 25)` ≈ #D2453E | `oklch(0.70 0.18 25)` | Deny、Stop、YOLO 警示 |
| `purple` | `oklch(0.55 0.15 310)` | `oklch(0.70 0.14 310)` | Codex 标签 |
| `blue` | `oklch(0.58 0.13 235)` | `oklch(0.70 0.12 235)` | 自定义 Agent 标签、文件类型 |

### 2.2 纸感分层（Surface）

| Token | Light | Dark | 用途 |
|---|---|---|---|
| `surface` | `oklch(0.975 0.009 80)` ≈ #F8F5F0 | `oklch(0.16 0.008 60)` ≈ #262422 | 页面底 |
| `surface-elevated` | `oklch(0.995 0.004 85)` ≈ #FEFDFB | `oklch(0.215 0.01 60)` ≈ #34312E | 卡片 |
| `fill` | `oklch(0.935 0.012 75)` ≈ #EDE8DF | `oklch(0.29 0.012 60)` | 输入框、次级按钮 |
| `fill-secondary` | `oklch(0.958 0.01 78)` | `oklch(0.25 0.01 60)` | 分组底、代码块底 |
| `border` | `oklch(0.90 0.014 70)` | `oklch(1 0 0 / 9%)` | 分割线、描边 |
| `label` | `oklch(0.22 0.02 45)` ≈ #34302B | `oklch(0.96 0.008 80)` | 主文字 |
| `label-secondary` | `oklch(0.50 0.02 55)` ≈ #7A7268 | `oklch(0.72 0.015 70)` | 副文字 |
| `label-tertiary` | `oklch(0.68 0.018 60)` ≈ #A9A196 | `oklch(0.52 0.012 60)` | 占位、时间戳 |

### 2.3 玻璃（Liquid Glass）

| Token | 值 | 说明 |
|---|---|---|
| `glass-fill` | `surface-elevated @ 62%` | 玻璃底色（iOS 26 用 `.glassEffect(.regular)`，其它端用 blur+半透明） |
| `glass-blur` | 24px, saturate 180% | |
| `glass-stroke` | 内描边 0.5pt `white @ 55%`（dark: `white @ 12%`） | 顶部高光 |
| `glass-shadow` | `0 0 0 0.5px oklch(0.3 0.03 50/0.1), 0 10px 30px oklch(0.3 0.03 50/0.10)` | 暖阴影 |
| `glass-tint-brand` | brand @ 18% | 主按钮玻璃变体（发送键、Allow 键） |

### 2.4 装饰球（Ambient Orbs）
- 左上：`brand-soft`，直径 360pt，偏移 (-120, -140)
- 右上：`amber-soft`，直径 300pt，偏移 (+140, -40)
- 底部中：`sage-soft`，直径 420pt，偏移 (0, +220)
- 模糊半径 60pt，opacity 0.8（dark 0.35）

## 3. 字体

| 样式 | iOS | 大小/字重 | 用途 |
|---|---|---|---|
| Large Title | SF Pro Display / 苹方 | 34 / Bold, tracking -0.5 | 页面大标题 |
| Title 1 | | 28 / Bold | 卡片大标题 |
| Title 2 | | 22 / Semibold | 会话名 |
| Headline | | 17 / Semibold | 列表主文字 |
| Body | | 17 / Regular | 消息正文 |
| Callout | | 16 | 按钮 |
| Subhead | | 15 | 副文字 |
| Footnote | | 13 | 时间、说明 |
| Caption / Eyebrow | | 12 / Semibold, tracking +1.2, 大写 | 分组标题（如 AGENT） |
| Mono | SF Mono / Menlo | 14 | 路径、命令、代码块 |
| Display（可选） | Fraunces / New York | 仅用于拉丁字母数字的大数字 | 待审批计数 |

## 4. 形状、间距、动效

- 圆角：sm 10 / md 14 / lg 18 / xl 22 / 2xl 26 / 胶囊 999
- 页面横向边距 20pt；卡片内边距 18pt；列表项高 56pt；Tab 栏高 64pt（玻璃胶囊，悬浮距底 12pt）
- 触控目标 ≥ 44pt
- 动效：`ease-out cubic-bezier(0.23,1,0.32,1)` 220ms；抽屉 `cubic-bezier(0.32,0.72,0,1)` 400ms；按压 scale 0.97 160ms
- 玻璃元素滚动时保持 morph（iOS 26 `GlassEffectContainer`）

## 5. 组件规范

| 组件 | 规格 |
|---|---|
| GlassNavBar | 高 52，圆角 26 胶囊，玻璃；左返回圆钮 44，中标题，右动作 |
| GlassTabBar | 4 项，胶囊玻璃，选中项 brand 圆底 + 白图标；审批项带 amber 角标 |
| PaperCard | surface-elevated，圆角 24，暖阴影 card |
| StatusDot | 8pt 圆：sage=在线/空闲，amber=运行中，danger=需审批，tertiary=离线 |
| AgentChip | 胶囊 28 高；Claude=amber-soft/amber 字，Codex=purple-soft，Custom=blue-soft |
| SessionCard | StatusDot + AgentChip + 来源 Chip + 时间；标题 Title2；路径 mono 在 fill-secondary 块中 |
| ApprovalCard | 玻璃卡 + danger/amber 左侧色条；命令 mono 块；三键：Deny（danger 描边）/ Allow once（fill）/ Allow（brand 实心） |
| MessageBubble | 用户：brand 实心，白字，圆角 22 右下 6；助手：surface-elevated，label 字，圆角 22 左下 6，带 Copy 按钮 |
| ToolCallCard | 折叠：图标 + 工具名 + 状态；展开：参数 mono |
| QuickReplyChip | 胶囊 fill 底，border 描边，Subhead |
| GlassInputBar | 胶囊玻璃，内含文本域 + 相机 + 发送圆钮（brand） |
| SegmentedGlass | 分段：选中项 brand-soft 底 + brand 描边 |
| Toggle | on=brand |
| DeviceCard | 设备名 Title2 + 连接方式 Chip（Tunnel/LAN/P2P/TS）+ 在线点 + 会话数 |
| QRScanner | 全屏相机，中央 260pt 玻璃取景框，四角 brand 高光 |

## 6. 各端映射

| 概念 | iOS | Android | 小程序 |
|---|---|---|---|
| 玻璃 | iOS 26 `.glassEffect()`；<26 `.ultraThinMaterial` + 描边 | `Modifier.blur` + 半透明 Surface（Compose 1.7 `graphicsLayer` RenderEffect） | `backdrop-filter: blur(24px)`（Skyline 支持） |
| 颜色 | Asset Catalog 或 Color(oklch→sRGB) | `Color(…)` Material 3 自定义 scheme | CSS 变量 |
| 字体 | SF Pro / 苹方 | Roboto / 思源黑体 | 系统字体 |
| 圆角 | `RoundedRectangle(cornerRadius:, style: .continuous)` | `RoundedCornerShape` | `border-radius` |

## 7. 深色模式
- 底色偏暖灰棕，不用纯黑；玻璃改为 `white @ 8%` 底 + `white @ 12%` 描边
- 装饰球 opacity 降到 0.35
- brand 提亮到 0.72 L 保证对比度
