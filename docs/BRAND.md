# YzVibe 品牌与 App 图标

![YzVibe Logo](assets/yzvibe-logo.png)

## 设计方向

**连接中的 V。** 两段奶油白带状笔画构成 V，在底部以弧形留缝交接，呼应手机与电脑之间持续传递的指令与反馈。V 同时对应 Vibe；粗轮廓和简洁构图让符号在手机桌面的小尺寸下仍能识别。

暖橙色延续现有 UI 的品牌色方向，奶油白呼应纸感内容表面。提示词目标色为暖橙 `#D66A43`、奶油白 `#FFF8ED`；生成位图有轻微色彩变化，这两个值用于后续品牌延展，不代表每个像素的精确颜色。UI 的实际颜色 token 仍以 [Theme.swift](../ios/Sources/YzVibeKit/Design/Theme.swift) 为准。

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
