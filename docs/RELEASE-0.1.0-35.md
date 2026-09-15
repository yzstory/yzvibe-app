# 柚子Vibe 0.1.0 (35)

## 界面优化

- 会话卡改用不透明内容面，任务标题前置；按目录分组时减少重复路径，搜索和未分组列表保留路径。
- 运行、空闲、待审批状态提供文字；来源与分支采用中性标签。
- 助手正文去除外层大卡片，扩大阅读宽度；工具摘要减少嵌套底色，普通入口收敛橙色强调。
- 内容卡圆角统一为 20pt，导航和输入区保留系统玻璃；审批标题展示实际操作类别。
- 大字号下分组路径和元信息纵向排列，运行指示器占位随字号缩放。
- 更新设计规范并保留历史快照。见 [界面对比](../design/reviews/2026-09-15-apple-design/README.md)。

## 验证

- iOS Debug 模拟器构建与 Release 归档通过；App、Widget 均为 0.1.0 (35)。
- 色板、聊天分组和审批相关测试共 16 项通过。
- 已检查深浅色截图与大字号可见区域；Mac 锁定期间未做手动点按、侧滑及真机验收。
- `git diff --check` 通过。

## 发布

2026-09-15 19:25:54（Asia/Shanghai）上传成功，Xcode 返回 `Upload succeeded`、`EXPORT SUCCEEDED`，上传命令退出码 0。

上传范围为 TestFlight Internal Only；内部测试组 `yzvibe` 已开启所有构建访问。Apple API 已确认 `processingState=VALID`、`buildAudienceType=INTERNAL_ONLY`、`internalBuildState=IN_BETA_TESTING`，`autoNotifyEnabled=true`。已进入内部测试，可在 TestFlight 更新。

Build ID：`20bbdf0b-65a4-4e89-ac54-869bb8435fa0`。
[TestFlight / App Store Connect](https://appstoreconnect.apple.com/apps/6811265232/testflight/ios)。
归档：`ios/build/YzVibe-build35.xcarchive`。
归档日志：`ios/build/design-archive35.log`。
上传日志：`ios/build/design-upload35.log`。
