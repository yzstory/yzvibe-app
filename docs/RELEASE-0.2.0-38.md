# 柚子Vibe 0.2.0 首版（build 38）

移动端营销版本升级为 0.2.0，iOS App、Widget 与 Android 统一 build 38。build 延续递增，便于 Android 覆盖升级。

## 本版内容

包含本轮双端 HTML 页面预览、Android 设备配置/诊断、工具折叠与会话到底部、原生改动/交付记录/上下文界面，以及 iOS 冷启动动画优化与 Android 界面适配。

HTML 预览需要支持 `/files/web-preview` 的新版连接器（npm 0.1.4）。

## 验证与产物

- iOS Release archive 成功，App 与 Widget 包内均为 0.2.0 (38)。
- Android assembleDebug、单元测试和 lintDebug 通过，aapt 确认 versionName=0.2.0、versionCode=38。
- 本轮仅修改版本配置；此前相关双端功能测试与模拟器界面回归证据见 progress.md。
- Android：`android/app/build/outputs/releases/YzVibe-0.2.0-38-debug.apk`（Debug 测试签名，未上传蒲公英）。
- APK SHA256：`f8845e59b917492263a4f3e4202a411b1d36aa0a794c4884ac19c79ba72e9388`。
- iOS：`ios/build/YzVibe-build38.xcarchive`。
- 日志：`ios/build/archive38.log`、`ios/build/upload38.log`。
- 源HEAD：8d80a68，包含未提交工作区改动。本轮未push源码。

## iOS 上传

2026-09-15 23:18:39（Asia/Shanghai），上传返回 `Upload succeeded`、`EXPORT SUCCEEDED`，退出码0。范围为 TestFlight internal only，按用户要求未继续等待 Apple 处理。
