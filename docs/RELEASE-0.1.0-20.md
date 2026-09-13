# 柚子Vibe 0.1.0 (20)

新增 iOS 原生回复朗读，过滤代码、常见命令和日志；支持停止、切换回复及与录音互斥，包含此前紧凑语音按钮改动。

源码 `543152f` 已推送 origin/main。125 项 iOS 测试通过，Release 归档成功；App 与 Widget 均为 build 20。

2026-09-13 15:13（北京时间）：使用新的 App Store Connect 团队 API 密钥，复用 Build 20 归档，云签名及上传成功。命令行明确返回 `Upload succeeded`、`Uploaded YzVibe`、`EXPORT SUCCEEDED`（退出码 0）。上传配置为 TestFlight Internal Only。

Apple API 已确认 `processingState=VALID`、`buildAudienceType=INTERNAL_ONLY`、`internalBuildState=IN_BETA_TESTING`，并开启自动通知。内部测试组 `yzvibe` 已确认开启所有构建访问，版本已进入内部测试。

先前失败原因：Xcode 账号读取失败；旧 API 密钥没有云签名权限且本机只有开发证书。新密钥已解决本次认证及云签名问题。

共享凭据保存在仓库外 `~/.appstoreconnect/credentials.env` 与 `~/.appstoreconnect/private_keys/`，配置和密钥文件权限 600，目录 700。后续上传已有归档：

```sh
source ~/.appstoreconnect/credentials.env
bash ios/scripts/upload-testflight.sh ios/build/YzVibe-build20.xcarchive
```

上述 Build 20 已上传成功，请勿再次重复上传同一构建号；后续发布请传入新构建的归档路径。上传失败时先确认 Apple 是否收到，再单独重试上传，无需重新归档。
