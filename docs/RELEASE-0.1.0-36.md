# 柚子Vibe 0.1.0 (36)

## 更新

- 会话中的 HTML/HTM 文件可在手机内渲染为页面，支持页面与源码切换。
- 独立、非持久化 WKWebView 支持 HTML 所在目录内的相对 CSS、JavaScript、图片与字体，以及页面内交互。
- 需要同步更新桌面连接器以提供 `/files/web-preview`；外部 CDN/API 不开放，含在线依赖的页面需先生成本地静态产物。

## 验证

- iOS 全量 92 项测试通过，包括真实 WKWebView 的 CSS、图片、脚本与按钮交互验证。
- Release 归档成功；App、Widget 均为 0.1.0 (36)。
- `git diff --check` 通过。

## 发布

2026-09-15 22:00:37（Asia/Shanghai）上传成功，Xcode 返回 `Upload succeeded`、`EXPORT SUCCEEDED`，退出码 0。上传范围为 TestFlight Internal Only。

归档：`ios/build/YzVibe-build36.xcarchive`。
日志：`ios/build/archive36.log`、`ios/build/upload36.log`。
[TestFlight / App Store Connect](https://appstoreconnect.apple.com/apps/6811265232/testflight/ios)。

Apple API 已确认 `processingState=VALID`、`internalBuildState=IN_BETA_TESTING`、`autoNotifyEnabled=true`，内部测试组 `yzvibe` 开启所有构建访问，已可在 TestFlight 更新。

Build ID：`347ba7cc-234e-415f-a9fd-e9ae15f3c182`。
