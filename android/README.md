# 柚子Vibe Android

原生 Kotlin / Jetpack Compose 客户端，最低 Android 10（API 29）。复用现有连接器，Claude Code、Codex App Server、OMP 仍在电脑运行。此目录的变更不修改 iOS 或连接器运行逻辑。

## 构建

需要 JDK 17、Android SDK Platform 35 / Build Tools 35、网络可访问 Google Maven 和 Maven Central。

```sh
cd android
./gradlew assembleDebug testDebugUnitTest lintDebug
```

首次构建会下载 Gradle 和依赖。设置 `ANDROID_HOME`，或在未跟踪的 `local.properties` 中配置 `sdk.dir`。不要把本机 SDK 路径、发布签名或服务商密钥提交进仓库。

测试安装包：`app/build/outputs/apk/debug/app-debug.apk`。当前为本机 debug 签名内部联调包，不是应用商店发布包。正式分发前需要独立的 Android 发布签名。

## 已实现

- 配对二维码、配对链接和 JSON；多设备切换、编辑名称和地址；主动局域网发现、备用地址身份检查。
- REST + WebSocket；同一 WS 上的快照与增量有序合并；前台指数退避重连，配对失效 / 原地址不可用 / 网络重连分别显示。
- 按目录分组、搜索、近七天筛选、全部展开收起、重命名、删除隐藏、恢复隐藏。
- 新建 Claude / Codex / OMP 会话，选择工作目录、继续上次会话、审批模式、模型和思考强度。会话内支持动态模型、模式和带触感的分档滑块。
- 流式聊天、工具详情、排队、立即引导、取消排队、继续队列、停止执行、返回最新。
- 每台电脑、每个会话独立草稿与附件。附件先复制进应用私有目录，最多 6 项，每项最多 20 MB。
- 本地持久化待投递记录及稳定消息 ID；上传中间结果保存；失败后先查回执，只有 `404 delivery_missing` 才允许重新投递。旧接口或会话不存在不会退回不可靠发送。
- Markdown 表格 / 代码 / 可选正文、复制、系统 TTS 朗读正文并过滤 fenced code 和常见日志。
- 照片 / 拍摄 / 文件 / 命令 / 技能统一入口；远程目录、Markdown、图片缩放、视频播放及文件分享。外部 HTTP(S) 链接交给浏览器。
- 审批、问题回答、保存建议规则、切换 Trust、规则删除；可选择审批前指纹 / 锁屏密码验证。
- OMP 模型配置按需读取，保存到当前连接器对应的终端配置；保留 revision 冲突保护，密钥不回显。
- 改动、上下文和任务交付记录查询；部分高级详情当前使用可选择的结构化文本展示。
- 1.6 秒可跳过的开场、会话加载指示、运行指示、系统任务通知（最多展示三项）。

## 明确的跨平台边界

1. **国内后台推送尚未接通。** `PushProvider` 是厂商适配接口，不是已可用的推送服务。连接器现有 `/devices/push` 是 APNs，Android 不会向它提交伪造 token。需选定厂商、包名签名及凭据，再实现供应商 SDK 和连接器发送适配；FCM 也不能当作所有国内手机的统一解决方案。
2. 当前应用离开前台即释放 WS，不保活轮询。普通通知只能反映最近一次收到的数据，不能替代可靠的后台审批推送。后台状态会在返回前台时补齐。
3. 按住说话使用 Android 12+ 的 on-device `SpeechRecognizer`，仅在设备确实提供该服务时启用。设备不支持则明确提示使用系统键盘，不会偷偷把音频发到云端。`SpeechProvider` 预留显式云端适配。音质、中文离线包和系统 TTS 可用性需真机确认。
4. Android 没有通用的 iOS 灵动岛；当前用系统任务汇总通知替代，不宣称支持所有厂商的实况窗。
5. 会话操作当前通过卡片菜单提供；新建目录、目录收藏、更精细的 diff/用量界面、离线历史缓存、分享进 App、分页历史，以及多品牌后台和无障碍体验仍需后续完善。此版本是可安装的首版联调包，尚未达到 iOS 全量体验对齐。

## 数据与连接

- 配对 token 用 Android Keystore AES-GCM 加密；凭据放 Authorization header，不放 URL。
- 禁止认证请求跟随重定向；公网地址要求 HTTPS，HTTP 仅允许本地私网地址。
- 草稿和投递使用应用私有目录的 AtomicFile。没有引入 Room：目前状态为小文档且单写入队列；加入大规模离线历史与全文搜索时再迁移数据库。
- 禁止云备份与设备迁移备份，避免聊天草稿和凭据文件被系统拷贝。
- OMP 配置没有后台定时同步；打开页面和保存时才请求。

## 验证

`ProtocolTest` 和 `ApiTest` 覆盖配对解析、七天筛选、快照/增量、工具合并、正文过滤、认证重定向、回执错误码与特殊字符路径。

独立联调连接器（不会加载真实 Agent 或用户会话）：

```sh
node android/tools/mock-connector.mjs
adb reverse tcp:29876 tcp:29876
```

测试配对链接写入 `/tmp/yz-android-smoke-pair.txt`。退出脚本清理自己的临时目录。配对码只能用一次，重新配对时重新启动测试脚本。

运行 `python3 android/tools/smoke.py` 可在隔离模拟器自动验收（会清空该模拟器中的 App 测试数据）。已在 API 35 模拟器验证：配对、会话列表、流式消息、审批允许、Markdown 表格、远程 Markdown 预览、切换会话及强制结束进程后的草稿恢复。相机、真实中文语音、触感、厂商通知与长时间网络切换需要 Android 真机验收。
