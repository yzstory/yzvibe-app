# iOS 0.1.0 (11) · Connector 0.1.1

本轮实现 2026-09-12 优化分析中的全部 P1，以及任务交付卡和连接诊断页。

## 可靠发送与恢复

- 文字与全部图片先原子保存到 iPhone 待发送箱，再清空输入框。任何图片上传失败都不会发送部分内容；失败条目可重试或还原输入，不覆盖新的草稿。
- 每条消息保留稳定的 `clientMessageId`。连接器将接收记录与队列一起落盘；重复请求返回同一记录，内容不同返回 409。响应丢失后先查询接收状态，Agent 接收结果不确定时不自动重新派发。
- WebSocket 每次连接成功都会触发补同步。会话、审批与已打开历史通过同一条事件通道的快照恢复，随后接收实时变化；终端导入会话同样支持。历史读取超时提供重试入口。
- 回复增量先写入可恢复日志再广播。重启恢复文字并将未完成任务标为中断；快照版本防止旧日志重复追加或覆盖最终正文。
- JSON / 入站 WebSocket 限制 256 KiB，上传限制 20 MiB；接收过程中执行限额。消息类型、长度、图片列表、发送模式和幂等 ID 在入队前校验。

## 新入口

- **会话 → 任务交付卡**：最近三轮结果显示在聊天页；右上角「更多 → 任务交付记录」可浏览最近 50 轮。详情含助手摘要、实际工具输出、退出码、关联文件和已记录产物。结束状态不代表测试通过；文件列表来自工具记录，并非完整 Git 归属证明。
- **设备 → 诊断**：检查当前/备用地址、连接器身份、往返耗时、Agent 安装与本机登录、推送配置及此手机注册状态。诊断导出仅含版本、状态、数量，排除地址、账户、设备名称、凭据和会话正文。

## 连接器升级

此构建的可靠发送、交付记录和诊断需要本轮 Connector 0.1.1（协议能力 `protocolVersion: 2`）。旧连接器不支持新的投递接口时，手机保留待发送内容并显示错误，不退回没有去重保证的发送接口。

从仓库运行连接器的电脑更新代码后，在 `connector/` 执行 `npm ci`，待正在执行的任务结束后执行 `node bin/yzvibe.js restart`。本轮不包含 npm 公共包发布。

## 验证

- 连接器：84 项测试通过，覆盖并发重复投递、接收记录写盘失败、附件不完整、重启恢复、旧日志回放、前台 WS 重连、终端会话快照与过大请求。
- iOS：iPhone 17 Pro / iOS 26.5 模拟器，91 项测试通过（53 XCTest + 38 Swift Testing），包括待发送箱、图片失败、响应丢失对账、App 重启、工具证据字段与有序快照恢复。
- 完整 App 与 Widget：Release 真机归档与模拟器构建成功，版本 0.1.0，构建号 11。
- [GitHub Actions #34684150559](https://github.com/yzstory/yzvibe-app/actions/runs/34684150559)：Node 20、Node 22 与 iOS 编译/测试全部通过，对应实现提交 `82fa16d`。
- 真机断网、真实 Agent 计费请求、APNs 实际送达、多手机通知和大规模长历史性能未在本轮自动化测试中验证。

## 内部测试上传

使用 Xcode 中已登录的开发者账号与仓库内的内部测试专用配置：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -exportArchive -archivePath ios/build/YzVibe-build11.xcarchive \
  -exportOptionsPlist ios/scripts/ExportOptions-TestFlight.plist \
  -allowProvisioningUpdates
```

配置固定构建号，并设置 `testFlightInternalTestingOnly = true`。上传回执与处理状态以 App Store Connect 为准。

### 上传回执

2026-09-12 16:49:54（Asia/Shanghai），Xcode 确认 `Upload succeeded` / `EXPORT SUCCEEDED`；App ID `6811265232`，版本 `0.1.0`，构建号 `11`，上传错误列表为空，包已进入 Apple 处理。

[App Store Connect / TestFlight](https://appstoreconnect.apple.com/apps/6811265232/testflight/ios)。受 macOS 辅助功能与屏幕录制授权未完成影响，本轮未能通过网页核验处理完成和内部测试组可安装状态；不将上传成功等同于已可安装。
