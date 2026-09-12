# iOS 0.1.0 (12)

## 本轮改进

- 设备配置与连接诊断展示设备 Token 认证状态。现有连接器已经为每台手机签发独立 Token，iOS 保存在钥匙串；HTTP 与 WebSocket 均校验认证。WebSocket 仅在 Authorization 请求头发送 Token，移除 URL 查询参数中的凭据。
- 诊断页可直接「使用此连接」，设备配置也可选择已有地址。切换先对目标地址核对连接器身份，再验证原设备 Token；不跟随重定向、不偷偷换用备用地址。验证成功才保存并重连，失败保留原配置。所选地址之后断线仍可自动故障转移，在线地址不会被后台地址推送或旧请求覆盖。
- 真机中的回环地址（如 `127.0.0.1`）显示不可用说明；局域网与远程地址可切换。切换保留连接器 ID、配对 Token、会话和历史。
- 交付卡显示在所属轮次最后一条回复下方，标注明确结束时间。开始下一轮后，上一轮卡片留在原位置。未能匹配已加载消息的旧记录只在「更多 → 任务交付记录」展示，避免旧卡片挂在当前任务底部。

本次兼容已经运行的 Connector 0.1.1，无需升级协议、重新配对或重启连接器；不涉及 npm 包发布。

## 验证

- 连接器 87 项测试通过，新增 HTTP / WebSocket Token 缺失、错误、跨地址使用、持久化及撤销回归。
- iOS 模拟器 101 项测试通过（53 XCTest + 48 Swift Testing），新增精确地址认证、失败回滚、旧请求竞态、WS 请求头，以及连续轮次交付卡归属回归。
- App / Widget build 12 Release 真机归档成功，版本与构建号均为 0.1.0 (12)。源码提交 `f001c51` 已 push 到 `origin/main`。
- [GitHub Actions #34688562856](https://github.com/yzstory/yzvibe-app/actions/runs/34688562856)：Node 20、Node 22、iOS 单元测试与完整 App / Widget 编译全部通过。
- 本轮未进行真机手动切换与页面操作验证；连接器测试使用隔离的临时实例，不中断当前运行中的任务。

## 内部测试

使用 `ios/scripts/ExportOptions-TestFlight.plist`，设置 `testFlightInternalTestingOnly = true`，上传至 [App Store Connect / TestFlight](https://appstoreconnect.apple.com/apps/6811265232/testflight/ios)。上传成功与 Apple 处理完成、内部测试组可安装是不同状态，以实际回执为准。

2026-09-12 18:29:11（Asia/Shanghai）首次上传在账号检查阶段失败：`Failed to Use Accounts`。当前 Xcode Apple Accounts 列表为空，尚未上传 build 12。已打开归档并请用户重新登录原开发者账号，登录后复用 `ios/build/YzVibe-build12.xcarchive` 继续上传，不需要重新构建。
