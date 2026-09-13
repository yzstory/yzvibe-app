# 柚子Vibe 0.1.0 (16)

2026-09-13：本次归档包含 Apple 端侧语音输入、应用显示名称、审批规则与会话 Trust、完成通知与通知偏好同步。介绍页源码同时纳入仓库。

- 源码提交：`cafe858`，已推送 origin/main。
- 验证：118 项 iOS 测试（53 XCTest + 65 Swift Testing）、103 项连接器测试通过；静态介绍页打包及 JavaScript 语法检查通过。
- Release 归档成功，App 和 Widget 均为 0.1.0 (16)，显示名称已核验。
- 归档：`ios/build/YzVibe-build16.xcarchive`，另已复制至 Xcode Organizer 的 `~/Library/Developer/Xcode/Archives/2026-09-13/YzVibe-build16.xcarchive`。

## 上传状态

**尚未上传成功。** 本次 xcodebuild 使用 TestFlight Internal Only 导出配置，在账号检查阶段返回 `Failed to Use Accounts`。这不能用于判断 Xcode 图形界面账号已经退出。图形控制多次返回 `cgWindowNotFound`，无法继续通过 Organizer 上传。

恢复桌面访问后，选择 build 16，Distribute App → TestFlight Internal Only → Distribute，核验上传完成回执。可复用本次归档，无需重新打包。

真机语音识别、耳机切换与录音手势仍需内部测试验证。

2026-09-13 后续核验：Xcode 界面已恢复，明确显示 `YzVibe 0.1.0 (16) uploaded`，Organizer 状态为 Uploaded to Apple，上传时间 09:15。此前上传阻塞已解除。
