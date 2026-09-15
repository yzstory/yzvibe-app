# 柚子Vibe 0.2.0 (39)

- 双端设备页顶部新增品牌 Logo「使用指南」入口，打开 https://vibe.yzcloud.icu/，引导安装连接器与扫码。
- 显示包内 App 版本与 build；各设备卡从对应连接器的 /health 读取真实版本，核对设备身份，读取失败显示暂不可获取。
- Android 点击连接器版本可重试；iOS 随设备端点/在线状态变更重新读取，重新进入页面也会读取。

验证：Android assembleDebug、单元测试、lintDebug 通过；iOS Release archive 通过。App、Widget、APK 包内版本均为 0.2.0 (39)。本次未做真机视觉验收。

Android：android/app/build/outputs/releases/YzVibe-0.2.0-39-debug.apk（Debug 测试签名）。
SHA256：60fddfe793876e6b8dba861663cff89baa375faaa48d4b938d597575267d0020。
iOS归档：ios/build/YzVibe-build39.xcarchive。
日志：ios/build/archive39.log、ios/build/upload39.log。
源HEAD：8d80a68，包含未提交工作区改动，未push。

2026-09-15 23:32:16（Asia/Shanghai）TestFlight internal only 上传返回 Upload succeeded / EXPORT SUCCEEDED，退出码0。未等待Apple处理。
