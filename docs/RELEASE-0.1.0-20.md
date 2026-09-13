# 柚子Vibe 0.1.0 (20)

新增 iOS 原生回复朗读，过滤代码、常见命令和日志；支持停止、切换回复及与录音互斥，包含此前紧凑语音按钮改动。

源码 `543152f` 已推送 origin/main。125 项 iOS 测试通过，Release 归档成功；App 与 Widget 均为 build 20。归档已复制至 Xcode Organizer 的 2026-09-13 目录。

2026-09-13：**尚未上传成功**。命令行上传返回 `Failed to Use Accounts`；随后尝试 Xcode 界面，工具返回 `cgWindowNotFound`，系统状态确认 `CGSSessionScreenIsLocked=Yes`。解锁后复用 build 20 归档，通过 TestFlight Internal Only 上传，无需重复打包。
