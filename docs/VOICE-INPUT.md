# 语音输入 v1

## 行为

- 轻点麦克风开始持续录音，再点或点完成结束；按住 250 ms 开始，松开结束，上滑 65 pt 锁定，左滑 65 pt 取消本段。
- 转写持续写入开始录音时的会话草稿，最终结果替换临时结果，追加到原有文字后。取消只撤销本段转写，不动原文和附件。
- 每段最多 60 秒；结束后最多等待 2 秒最终结果，未收到最终结果时保留已有文字。
- 录音和最终结果等待期间禁用发送；转写完成可编辑，任务运行中显示排队发送和立即引导，复用现有可靠投递流程，附件准备期间也禁用这些入口。
- 切换会话、进入后台、音频中断或输入设备变化时停止并保留当前转写，不自动重新开启麦克风。旧回调不得修改新的会话或覆盖外部编辑。
- 文字草稿复用 AppStore 的会话内存草稿，未发送草稿不保证跨 App 强制退出恢复。不会保存原始录音文件。

## Apple 实现

使用 iOS 17+ 的 AVAudioEngine 与 SFSpeechRecognizer；检查 supportsOnDeviceRecognition，明确设置 requiresOnDeviceRecognition = true。不支持时显示错误并保留键盘输入，不降级到 Apple 服务端或第三方云端。中文为默认识别语言，并提供少量开发术语 contextualStrings。

第一版选择覆盖当前最低系统版本的 Apple 端侧 API。SpeechAnalyzer 可作为后续 Apple provider 的内部升级，UI 和消息协议无需因此变动。新系统或语言识别模型缺失时，当前版本不自行安装模型。

## 可替换识别接口 / Android

SpeechRecognitionProvider 对外只暴露 start(configuration, receive)、finish、cancel。配置使用语言标识和术语列表；事件使用完整转写快照（含最终标记）、归一化音量、录音中断、错误说明。采集和识别由 provider 管理，UI 不依赖 AVAudioPCMBuffer 或厂商响应结构。

Android 可以实现同样的接口语义，选择端侧或云端 provider。后续云端实现应在 provider 内转换 PCM/压缩音频与流式协议，使用后端签发的短期凭据，不把供应商长期密钥写入移动 App。当前无云端 URL、Key、上传或自动降级行为。

AppStore 的演示模式注入 DemoSpeechRecognitionProvider，仅产生明确标记“演示转写”的示例，不请求麦克风权限。真实设备连接路径始终使用 Apple provider。

## 验证边界

回归覆盖临时结果修订、取消、最终结果、打断、并发编辑、权限取消和跨会话迟到回调。真机须补验中文/中英混说准确率、离线模型可用性、耳机与来电中断；模拟器演示不能代替真实音频识别验证。
