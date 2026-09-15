# 柚子Vibe 0.1.0 (37)

## 开屏优化

- 每次冷启动显示品牌欢迎页：日常约 1.5 秒（1.25 秒展示 + 0.25 秒淡出），安装后首次约 1.9 秒。
- 从场景进入前台开始计时；离开前台取消计时，回来后重新给予完整展示时间，避免后台消耗展示时间。
- 已完成开屏后，从后台返回不重播；通知和配对深链跳过欢迎页。
- 缩放幅度从 0.65 收敛到 0.92，减少旋转和位移；保留轻点跳过、减少动态效果适配。

## 验证

Release 归档通过，App 与 Widget 版本均为 0.1.0 (37)，`git diff --check` 通过。此次未做真机动画观感验收。

## 发布

归档：`ios/build/YzVibe-build37.xcarchive`。
日志：`ios/build/archive37.log`、`ios/build/upload37.log`。

2026-09-15 22:11:06（Asia/Shanghai）上传成功，返回 `Upload succeeded`、`EXPORT SUCCEEDED`，退出码 0。上传范围为 TestFlight Internal Only；按用户要求，不等待或查询 Apple 处理及内部测试可用状态。
