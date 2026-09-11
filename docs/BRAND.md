# YzVibe 品牌与 App 图标

![YzVibe Logo](assets/yzvibe-logo.png)

## 设计方向

**手写 vibe · 远程指针。** 橙色小写连笔字承接参考图的流动感，粗笔画、上扬走势与底部收笔形成完整标识。右上角用鼠标指针替代飞机，呼应从手机操控桌面 AI 编程会话的产品用途。

配色跟随新版「焦橙纸感」UI：焦橙 `#C75015` 与暖纸色 `#F9F6F2`。这些是生成提示词的目标色，位图会有轻微色彩变化；界面颜色以 [Theme.swift](../ios/Sources/YzVibeKit/Design/Theme.swift) 为准。图标使用暖纸色满底，保留完整的手写词标。

旧版 V 图形和原提示词保存在 [design/brand/archive/v1](../design/brand/archive/v1/)，可随时回溯。

## 交付资源

| 资源 | 路径 | 用途 |
| --- | --- | --- |
| 生成原图 | [yzvibe-logo-original.png](../design/brand/yzvibe-logo-original.png) | 保留原始生成结果 |
| 标准 Logo | [yzvibe-logo.png](assets/yzvibe-logo.png) | 1024 × 1024 RGB PNG，README 和品牌展示 |
| iOS AppIcon | [AppIcon.png](../ios/App/YzVibe/Assets.xcassets/AppIcon.appiconset/AppIcon.png) | 与标准 Logo 相同的 1024 × 1024 图标 |
| 生成提示词 | [logo-prompt.txt](../design/brand/logo-prompt.txt) | 完整设计约束，可用于后续迭代 |
| 架构图 | [architecture.svg](assets/architecture.svg) | 可缩放、可直接嵌入 README 的矢量图 |

Logo 使用内置 `image_gen` 工具生成，随后使用系统 `sips` 等比缩放到 1024 × 1024。它是位图资源，不是矢量源文件；架构图为独立编写的 SVG，结构化说明见 [ARCHITECTURE.md](ARCHITECTURE.md)。

## iOS 接入

- 使用完整正方形、无透明通道的图像，未预先裁切外轮廓圆角。
- `Assets.xcassets/AppIcon.appiconset/Contents.json` 指向统一的 1024 图标源。
- [project.yml](../ios/project.yml) 已设置 `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`；资源目录包含在现有 App 源码路径中。
- 在 `ios/` 运行 `xcodegen generate` 后，由 Xcode 资源编译器处理图标。
- 当前提供默认外观；没有单独制作深色、着色或分层 Icon Composer 版本。

展示时保持正方形比例和图形留白，不拉伸、不额外加外框。README 可以直接缩小使用标准 Logo；后续若制作单色印刷物或需要透明底，应单独制作对应资产。
