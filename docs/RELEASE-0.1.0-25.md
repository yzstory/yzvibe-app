# 柚子Vibe 0.1.0 (25)

- 新建会话仅显示 Claude、Codex、OMP。
- OMP 只读取电脑端明确配置的模型，支持手机通过 HTTPS 同步 Base URL、API Key、Model Name，密钥不回显。
- 回复里的本地 Markdown、图片和视频支持 App 内查看；Markdown 默认渲染，支持相对链接和图片，图片可全屏缩放，视频下载后播放。
- 修正中文、空格和特殊字符路径编码，外链继续在浏览器打开。

验证：118 项连接器测试、133 项 iOS 测试通过；OMP 原生配置读取验证通过。

发布状态：2026-09-14 已通过 App Store Connect API 密钥上传；Apple 处理状态 VALID，内部测试状态 IN_BETA_TESTING，yzvibe 内部组可安装 0.1.0 (25)。
