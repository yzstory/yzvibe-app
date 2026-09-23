# 柚子Vibe 0.2.0 (41)

- 优化会话滚动和输入性能：消息区独立观察更新，系统 List 按需渲染并复用消息行，固定历史窗口起点，合并流式滚动请求。
- 验证：完整模拟器编译、Release archive 成功；14 项测试通过，包含 80 条长消息按需渲染、草稿修改、视口高度切换、流式回复增长及消息缓存/排队/分组回归。真机流畅度待复测。
- App 和 Widget 包内版本均为 0.2.0 (41)，Android 源码同步 build 41，本轮未发布 Android。
- 源码 HEAD：52b2d45b089ce17a35efacf2c0b7f05f0cc8892f + dirty 工作区，未提交或 push。
- 归档：ios/build/YzVibe-build41.xcarchive；校验副本 /tmp/YzVibe-0.2.0-41.xcarchive.zip。
- 归档 ZIP SHA256：11d52aada9562a067c429eef392f18d81387d06ac16a09d4ed4ac2012926e25e。
- 日志：ios/build/archive41.log、ios/build/upload41.log。
- 2026-09-23 08:39:47（Asia/Shanghai）TestFlight internal only 上传返回 Upload succeeded / EXPORT SUCCEEDED，退出码 0。
- 按要求未等待 Apple 后续处理或验证，上传成功不代表此刻已经可安装。
