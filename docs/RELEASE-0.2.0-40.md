# 柚子Vibe 0.2.0 (40)

- 修复发送消息后列表偶发空白的布局路径：消息窗口使用实际高度，内容与键盘视口布局后合并滚动请求，避免在布局回调内同步反复滚动。
- iOS App / Widget 版本核验为 0.2.0 (40)；Android 源码同步 build 40，本轮未构建或发布 Android。
- 验证：完整 iOS Simulator 编译、Release archive 成功；消息缓存、排队可见性和消息分组 13 项测试通过。偶发问题仍待真机复测。
- 源码：52b2d45b089ce17a35efacf2c0b7f05f0cc8892f + dirty 工作区，未提交或 push。
- 归档：ios/build/YzVibe-build40.xcarchive；本地校验副本 /tmp/YzVibe-0.2.0-40.xcarchive.zip。
- 归档 ZIP SHA256：3edc15dd831b85c8575061b0f367b2c786047eec5e37b25c84da0f759acd8ce3。
- 日志：ios/build/archive40.log、ios/build/upload40.log。
- 2026-09-22 21:37:49（Asia/Shanghai）TestFlight internal only 上传返回 Upload succeeded / EXPORT SUCCEEDED，退出码 0。
- 按用户要求结束，未等待 Apple 后续处理或验证；不代表此刻已经可安装。
