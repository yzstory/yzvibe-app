# 柚子Vibe Android

最新打包版本：**0.2.0 (39)**。iOS 已上传 TestFlight；Android 提供 Debug 测试 APK。详见 [本版发布记录](../docs/RELEASE-0.2.0-39.md)。

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
- 原生改动对比（范围选择、按文件折叠、增删颜色）、上下文与账号额度图表、任务交付卡及可展开的工具输出。
- 1.6 秒可跳过的开场、会话加载指示、运行指示、系统任务通知（最多展示三项）。
- 边到边：`enableEdgeToEdge()` 绘制到系统栏之下，系统栏颜色和图标明暗跟随应用内「外观」而不是写死在 `styles.xml`；列表用 `contentPadding` 让位，输入条用 `safeDrawing` 的底部并集同时盖住导航栏和输入法。
- 自适应导航：`NavigationSuiteScaffold` 在手机用底部栏、平板 / 展开的折叠屏 / 桌面用侧边导航栏；会话内和键盘弹出时隐藏导航区。设备卡和会话卡按可用宽度自动分列。
- 预测式返回：会话页用 `PredictiveBackHandler`，返回手势推进时页面跟着缩放、位移、淡出，松手取消会回弹，对齐 iOS 的边缘滑动返回。
- 外观可选自动 / 浅色 / 深色；跟随系统「增强对比度」切换到高对比色板。四套色板与 iOS `Palette` 逐色对齐，含 Material 配色表装不下的琥珀 / 鼠尾草 / 紫 / 蓝。
- 顶部胶囊 Toast 承接一过性提示（3 秒自动消失），只有真正需要确认的失败才弹对话框。
- 「我」页可切换按目录分组、只看近七天、显示终端会话，与会话页共用同一份持久化偏好。

## 明确的跨平台边界

1. **国内后台推送尚未接通。** `PushProvider` 是厂商适配接口，不是已可用的推送服务。连接器现有 `/devices/push` 是 APNs，Android 不会向它提交伪造 token。需选定厂商、包名签名及凭据，再实现供应商 SDK 和连接器发送适配；FCM 也不能当作所有国内手机的统一解决方案。
2. 当前应用离开前台即释放 WS，不保活轮询。普通通知只能反映最近一次收到的数据，不能替代可靠的后台审批推送。后台状态会在返回前台时补齐。
3. 按住说话使用 Android 12+ 的 on-device `SpeechRecognizer`，仅在设备确实提供该服务时启用。设备不支持则明确提示使用系统键盘，不会偷偷把音频发到云端。`SpeechProvider` 预留显式云端适配。音质、中文离线包和系统 TTS 可用性需真机确认。
4. Android 没有通用的 iOS 灵动岛；当前用系统任务汇总通知替代，不宣称支持所有厂商的实况窗。
5. 会话操作当前通过卡片菜单提供；新建目录、目录收藏、分享进 App、分页历史，以及多品牌后台仍需后续完善。
6. 大屏只做到「导航区换侧栏 + 卡片分列」。没有做列表-详情双栏：`ListDetailSceneStrategy` 要求先迁移到 Jetpack Navigation 3，而本应用目前用的是状态驱动的导航，迁移范围超出本轮。宽窗口下页头和搜索框会被拉满整行，暂未限制最大宽度。
7. 预测式返回用的是 `androidx.activity` 的 `PredictiveBackHandler`，不是 `androidx.navigationevent`：后者要求 compileSdk 36，本机 SDK 只装了 Platform 35，且本应用没有用 Navigation 3。两者产出的手势体验一致。

## 数据与连接

- 配对 token 用 Android Keystore AES-GCM 加密；凭据放 Authorization header，不放 URL。
- 禁止认证请求跟随重定向；公网地址要求 HTTPS，HTTP 仅允许本地私网地址。
- 草稿和投递使用应用私有目录的 AtomicFile。没有引入 Room：目前状态为小文档且单写入队列；加入大规模离线历史与全文搜索时再迁移数据库。
- 禁止云备份与设备迁移备份，避免聊天草稿和凭据文件被系统拷贝。
- OMP 配置没有后台定时同步；打开页面和保存时才请求。

## 验证

`ProtocolTest` 和 `ApiTest` 覆盖配对解析、七天筛选、快照/增量、工具合并、正文过滤、认证重定向、回执错误码与特殊字符路径。

`ui/Previews.kt` 提供手机 / 折叠屏 / 平板 / 桌面四档 `@Preview`，改自适应布局或配色前后先在 Studio 里过一遍。

`DesignFlowTest` 和 `ParityFlowTest` 需要模拟器加下面的隔离连接器。注意 mock 的配对 token 是一次性的：手工连过一次就要重启 mock 再跑，否则第一个 `await` 会等到「配对已失效」超时。

独立联调连接器（不会加载真实 Agent 或用户会话）：

```sh
node android/tools/mock-connector.mjs
adb reverse tcp:29876 tcp:29876
```

测试配对链接写入 `/tmp/yz-android-smoke-pair.txt`。退出脚本清理自己的临时目录。配对码只能用一次，重新配对时重新启动测试脚本。

运行 `python3 android/tools/smoke.py` 可在隔离模拟器自动验收（会清空该模拟器中的 App 测试数据）。已在 API 35 模拟器验证：配对、会话列表、流式消息、审批允许、Markdown 表格、远程 Markdown 预览、切换会话及强制结束进程后的草稿恢复。相机、真实中文语音、触感、厂商通知与长时间网络切换需要 Android 真机验收。

### Android 视觉回归

主页面使用完整的 Material 3 深浅色主题，跟随系统外观；品牌橙色、标题层级和中性色与 iOS 保持一致。会话卡片优先显示标题，聊天正文继承当前主题，审批卡区分风险与操作，“我”页面按功能分组。

新增 `DesignFlowTest`：在隔离模拟器检查搜索、切换会话后的草稿保留、消息发送、审批拒绝及主导航，并生成六张页面截图。运行前停止单独启动的 mock connector；脚本会自行创建测试后端，不调用真实 Agent。

```sh
cd android
./gradlew assembleDebug assembleDebugAndroidTest testDebugUnitTest lintDebug
cd ..
python3 android/tools/design-review.py
```

需要 JDK 17、Android SDK 和已启动的隔离模拟器。可用 `ANDROID_SERIAL` 指定模拟器。**脚本清空该模拟器内的 App 测试数据**，分别验证深色、浅色及 1.3 倍字体，结束后恢复系统外观与字体设置。截图与结果位于 `android/app/build/outputs/design-review/`，不进入 Git。单独运行 instrumentation 时，须提供 `pairUri` 参数，否则此用例跳过。

### 双端预览与 Android 功能对齐（2026-09-15）

- HTML 文件默认渲染为页面，可切换源码；支持 HTML 所在目录及子目录中的 CSS、JS、图片、字体与 JSON。页面内 JavaScript 可交互。网页不能访问连接器 API、手机文件或外部网络；依赖外部 CDN/后端的项目需先生成包含本地资源的静态产物。
- **HTML 预览需要电脑运行本次更新后的连接器**（新增认证接口 `/files/web-preview`）。安装新版手机 App 不会自动升级电脑进程。旧连接器会提示更新；普通文件预览继续可用。
- 设备卡片直接进入配置或诊断，配置支持候选地址选择、身份和 Token 验证后保存；诊断支持耗时、Agent 可用性/登录状态、待办数量及脱敏导出。
- 进入会话后定位最新消息末尾，阅读旧消息时不强制拉回；连续纯工具/思考消息合并为一个可展开的活动卡，保留用户回复、附件与审批边界。
- 新增 `ParityFlowTest` 用长回复、80 次工具调用、真实 Git 差异及 HTML 资源运行完整验收：

```sh
# 同上先构建 App 与 androidTest，使用隔离模拟器（会清除其中的 App 测试数据）
YZVIBE_UI_SUITE=parity python3 android/tools/design-review.py
```

结果与截图位于 `android/app/build/outputs/parity-review/`。
