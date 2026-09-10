# YzVibe 设计规范（多端共用）

> **方向 B「焦橙纸感」** —— 结构全部交给系统（大标题 / List / Tab 栏），品牌只通过一个焦橙和一层暖纸出现。
> 本文是 iOS / Android / 小程序三端的视觉唯一来源；各端把 token 映射到自己的原生系统。
> 备选方向与决策依据见 [design/directions/](../design/directions/)。

## 1. 设计立场

- **结构还给系统。** 大标题、搜索、Section、侧滑、Tab 栏一律用平台原生组件，不自绘。用户已经会用它们了。
- **只有一个强调色。** 焦橙 `#C75015` 承担 tint、主按钮、用户气泡、选中态。其余状态用中性或语义色，界面上不出现第五种彩色胶囊。
- **橙的面积控制在 10% 以内。** 大面积橙块只有一处：用户消息气泡（对应 Messages 的蓝气泡）。
- **暖纸中性。** 底色是偏暖的纸 `#F9F6F2`，不是系统的冷灰，也不是纯白。深度靠**发丝描边**而不是投影。
- **玻璃只给真正漂浮的东西。** 输入条、Toast、扫码取景框。内容层永远不透明。
- **不做背景装饰。** 上一版的三个柔焦装饰球已移除 —— 它们是「不像 iOS」的主要来源，也让系统玻璃没有正确的折射对象。

## 2. 颜色 Token

颜色**直接用 sRGB hex 定义**。上一版用 oklch 换算，文档标注的 `#C2573A` 和实际渲染的 `#DE602F` 差了整整一档、深色底比设计意图暗了一档；改用 hex 后文档与代码不会再漂。
唯一来源：[Theme.swift](../ios/Sources/YzVibeKit/Design/Theme.swift)。每次改色都要跑 `PaletteContrastTests`。

### 2.1 品牌与语义色

| Token | Light | Dark | 对比度 | 用途 |
|---|---|---|---|---|
| `brand` | `#C75015` | `#FF9868` | 白字 4.58:1 / 深字 8.19:1 | 主按钮、用户气泡、tint、选中态 |
| `brandText` | `#A63D02` | `#FFB08A` | 浅橙底 5.30:1 | 胶囊里的橙色文字、小字强调 |
| `brandSoft` | `#FFE5D8` | `#3A2A22` | — | 胶囊底、选中底 |
| `brandInk` | `#FFFFFF` | `#241812` | — | 压在 brand 上的文字 |
| `sage` | `#1B7046` | `#5FD08E` | 纸底 5.65:1 | 在线、空闲、已允许 |
| `danger` | `#C4261C` | `#FF6961` | 纸底 5.35:1 | 拒绝、停止、待审批 |
| `amber` | `#B0761A` | `#E8B45C` | 纸底 3.58:1 | 中风险色条、图标（不承载正文） |
| `amberText` | `#8A5A0E` | `#E8B45C` | 琥珀底 5.19:1 | 琥珀胶囊里的文字 |
| `purple` / `blue` | `#6E4B9E` / `#1F6FA8` | `#C09AE8` / `#6FB6E8` | — | 设置页图标底，不用于状态语义 |

**橙色的使用规则**：`brand` 用于填充和 tint；小字、链接、胶囊文字一律用 `brandText`。
这是苹果自己的做法 —— `systemOrange #FF9500` 配白字只有 2.20:1，苹果从不让橙色承担文字对比。

### 2.2 纸感分层（Surface）

| Token | Light | Dark | 用途 |
|---|---|---|---|
| `surface` | `#F9F6F2` | `#201E1B` | 页面底（暖纸 / 暖灰棕，都不用纯白或纯黑） |
| `surfaceElevated` | `#FFFDFA` | `#2C2A27` | 卡片、气泡 |
| `fill` | `#EFEAE2` | `#383530` | 输入框、次级按钮、中性胶囊 |
| `fillSecondary` | `#F4F0E9` | `#322F2B` | 代码块底 |
| `border` | `#E6DFD5` | `white 12%` | 发丝描边、分割线 |
| `label` | `#231813` | `#F5F2EE` | 主文字（16.1:1 / 14.9:1） |
| `labelSecondary` | `#6D6059` | `#B5AEA6` | 副文字（5.62:1 / 7.58:1） |
| `labelTertiary` | `#877E78` | `#8A837B` | 时间戳、占位（3.69:1 / 4.44:1） |

### 2.3 增强对比度

系统「增强对比度」开关打开时切到 `lightHighContrast` / `darkHighContrast`：
主色压到 `#A83B00`（白字 6.38:1），三级文字提到 `#6F675F`（5.16:1），描边加深。
由 `PaletteProvider` 读 `\.colorSchemeContrast` 自动完成，视图层不用管。

### 2.4 玻璃（只给漂浮层）

| Token | 值 | 说明 |
|---|---|---|
| 材质 | iOS 26 `.glassEffect(.regular)`；< 26 用 `.regularMaterial` | 不再手绘白色高光渐变 |
| 描边 | 0.5pt `border` | 系统材质自带高光，只补一圈边 |
| 降低透明度 | `accessibilityReduceTransparency` 打开时换成不透明 `surfaceElevated` | 必须处理，否则文字读不清 |
| 用在哪 | 输入条、Toast、配对遮罩、扫码取景框 | 仅此四处 |

## 3. 字体

全部基于系统文本样式，**跟随动态字体缩放**。不再写死 pt —— 需要固定尺寸的控件用 `@ScaledMetric`。

| 语义 | 映射 | 用途 |
|---|---|---|
| `yzLargeTitle` | `.largeTitle` bold | 系统大标题（由 `.navigationTitle` 提供） |
| `yzTitle2` / `yzTitle3` | `.title2` / `.title3` semibold | 卡片标题、会话名 |
| `yzHeadline` | `.headline` | 列表主文字 |
| `yzBody` | `.body` | 消息正文、设置行 |
| `yzCallout` | `.callout` semibold | 按钮 |
| `yzSubhead` / `yzSubheadStrong` | `.subheadline` | 副文字 |
| `yzFootnote` / `yzFootnoteStrong` | `.footnote` | 时间、说明、胶囊 |
| `yzCaption` / `yzEyebrow` | `.caption` | 分组标题、辅助信息 |
| `yzMono` / `yzMonoBody` | `.footnote` / `.subheadline` + `.monospaced` | 路径、命令、代码 |

## 4. 形状、间距、动效

- 圆角：sm 8 / md 10 / lg 14 / xl 16 / 2xl 20 / 卡片 16 / 胶囊全圆。比上一版整体收紧一档，贴近系统列表。
- 页面横向边距 20pt；卡片内边距 14–16pt；触控目标 ≥ 44pt
- 动效：`ease-out cubic-bezier(0.23,1,0.32,1)` 220ms；抽屉 `cubic-bezier(0.32,0.72,0,1)` 400ms；按压 scale 0.97
- 阴影几乎不用：卡片只有 `shadow 4% / radius 2`，层级靠描边和留白

## 5. 组件规范

| 组件 | 规格 |
|---|---|
| 导航 | 系统 `NavigationStack` + `.navigationTitle` + `.searchable`；不自绘导航条 |
| Tab 栏 | 系统 `TabView`，`.tint(brand)`，审批项用系统 `.badge` |
| 列表 | 会话 / 审批用 `List(.plain)` + 每行一张 `PaperCard`；设置类用 `List(.insetGrouped)` |
| PaperCard | `surfaceElevated`，圆角 16，1pt `border` 描边，阴影 4% |
| StatusDot | 8pt：`sage`=空闲/在线，`brand`=运行中，`danger`=待审批/出错，`labelTertiary`=已关闭 |
| Chip | 胶囊，`.footnote` semibold；Claude=`brandSoft`/`brandText`，Codex 与自定义=`fill`/`labelSecondary` |
| SessionCard | StatusDot + AgentChip + 来源 + 时间；标题 `.title3`；路径 mono 块；侧滑=停止 / 复制路径 |
| ApprovalCard | 纸卡 + 左侧 4pt 风险色条；命令 mono 块；拒绝（描边）/ 允许（brand 实心）/ 总是允许…（菜单） |
| MessageBubble | 用户：`brand` 实心 + `brandInk`，圆角 20 右下 6；助手：`surfaceElevated` + 描边，圆角 20 左下 6 |
| GlassInputBar | 圆角 22 玻璃；相机 / 命令 / 会话选项胶囊 / 发送圆钮（brand 实心 38pt） |
| 空状态 | 一律 `ContentUnavailableView`，不自绘 |
| 分段控件 | 一律系统 `Picker(.segmented)` |

## 6. 各端映射

| 概念 | iOS | Android | 小程序 |
|---|---|---|---|
| 结构 | `NavigationStack` / `List` / `TabView` | `Scaffold` + `LargeTopAppBar` + `LazyColumn` + `NavigationBar` | 原生导航栏 + `scroll-view` |
| 颜色 | `Palette`（hex） | Material 3 自定义 scheme | CSS 变量 |
| 字体 | 系统文本样式 + 动态字体 | `MaterialTheme.typography` + `fontScale` | `rpx` + 系统字号设置 |
| 玻璃 | `.glassEffect()` / `.regularMaterial` | `Modifier.hazeEffect` 或半透明 Surface | `backdrop-filter: blur(24px)` |
| 圆角 | `RoundedRectangle(cornerRadius:, style: .continuous)` | `RoundedCornerShape` | `border-radius` |

## 7. 无障碍红线

1. **动态字体**：不写死字号。违反了在大字号下会截断。
2. **对比度**：正文 4.5:1、非文本 3:1。由 [PaletteContrastTests](../ios/Tests/YzVibeKitTests/PaletteContrastTests.swift) 在 CI 上守住。
3. **降低透明度**：玻璃必须有不透明回落。
4. **增强对比度**：走 `lightHighContrast` / `darkHighContrast`。
5. 纯图标按钮必须有 `accessibilityLabel`；纯装饰元素 `accessibilityHidden(true)`。
