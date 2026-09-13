# 柚子Vibe 0.1.0 (21)

语音入口改为麦克风图标加“语音”标签的紧凑胶囊，最小 76 × 44 点；与左侧选项保持 6 点间距。语音按钮独立占位，左侧选项在宽度不足时横向滚动，保留按住录音和上滑取消交互。

代码：`96374a6`。Release 归档通过，主 App 和 Widget 构建号均为 21，diff 检查通过。此次仅调整布局和标签，未重复运行业务逻辑测试；尚未进行真机视觉验收。

2026-09-13 15:27（北京时间），通过共享 App Store Connect API 密钥上传成功，命令行返回 `Upload succeeded`、`EXPORT SUCCEEDED`（退出码 0）。上传范围为 TestFlight Internal Only。Apple API 已确认 `processingState=VALID`、`internalBuildState=IN_BETA_TESTING`，自动通知开启，内部测试可用。
