# 进度日志

## 会话 7 — 2026-09-12：认证、地址选择与交付卡归属（代码完成，上传待账号登录）
- 用户要求核验连接器 Token 认证、让诊断中的候选连接可手动切换；当前代码已有独立设备 Token、HTTP 与 WS 鉴权、Keychain 保存。
- 截图显示三个候选地址（局域网、隧道、127.0.0.1），现有诊断只展示检查结果，设备配置只提供文本地址。
- 已实现精确地址身份/Token 验证、诊断与配置候选切换、旧请求竞态保护、在线地址推送保留选择；WS 不再把 Token 放进 URL。
- 用户追加旧交付卡停留在底部的问题：已解码现有 run 的消息关联，将卡片定位到自己的轮次，无法关联的旧记录保留在历史入口。
- 连接器 87 项、iOS 101 项回归通过；App / Widget build 12 Release 归档成功，随后沿用授权 push 和内部测试上传。
- 中间错误：新测试方法漏写 func，已修正并完整重跑成功。
- 实现提交 f001c51 已 push；GitHub CI 34688562856 的 Node 20/22、iOS 单元测试与完整 App / Widget 编译全部通过。
- build 12 于 18:29:11 在上传账号检查阶段失败（Failed to Use Accounts）；Xcode Apple Accounts 实际列表为空。已打开归档并异步请用户登录原开发者账号，等待恢复后继续上传。

## 会话 6 — 2026-09-12：实现与发布（上传成功，处理/内测组待核验）
- 32 个文件改动已提交为 82fa16d 并 push 到 origin/main。
- build 11 于 16:49:54 成功上传 App Store Connect（App ID 6811265232），内部测试专用，无上传错误，进入 Apple 处理。
- 完整 App/Widget 模拟器构建通过；本机诊断实际读取 Claude/Codex 版本及已登录状态，未调用模型。
- UI 阻塞原因已确认：Computer Use 的辅助功能与屏幕录制授权未完成；无法核验网页上的处理完成/内测组可安装状态。
- GitHub Actions #34684150559 全部通过：Node 20、Node 22、iOS 单元测试、完整 App/Widget 编译。
- 最终后端 84/84、iOS 91/91 测试通过；App 与 Widget build 11 Release 归档成功。新增可复用内部测试 ExportOptions，更新协议和能力说明。
- 网页/原生 UI 控制工具三次超时，页面验证暂不可用；沿用本机成功上传过 build 10 的 Xcode 账号完成后续发布。
- 发送恢复、持久化、快照同步和两项扩展已完成；首轮 iOS 模拟器 90 项测试全通过（53 XCTest + 37 Swift Testing），后端首轮 82 项全通过。
- 补充了终端会话快照接管、读取超时反馈、交付历史入口与磁盘写失败时接收记录回滚；开始最终回归。
- 确认 build 10 已通过现有 Xcode 账号上传，将使用 build 11，并保留 TestFlight 内部测试专用分发配置。
- 用户授权全部 P1 修复、任务交付卡、连接诊断页，并提交 push 与 TestFlight 内部测试发布。
- 当前工作区仅上轮分析文档改动；当前 App/Widget 构建号 10。将先实现并验证，再发布。
- 已实现服务端接收去重记录、队列派发状态、流式日志恢复、请求限额；新增 runs 与 diagnostics 接口、按 WS 顺序传输的恢复快照。
- iOS 已接入持久化待发送箱、交付卡/详情和设备诊断页，开始编译与故障场景回归。
- 中间检查：连接器原有 73/74 通过，清理计数因新增日志文件变化失败，已补齐过期会话日志清理；Swift 编译需沙箱外缓存权限，已获准。首轮编译发现泛型函数内嵌类型限制，已移出。

## 会话 5 — 2026-09-12：优化与拓展分析
- 恢复规划与历史审查；确认当前工作区干净，读取结构、测试配置和旧审查边界。
- 计划从真实消息链路、持久化/性能、Agent 适配、iOS 产品体验四方面复核；本轮只交付分析文档。
- 读取服务端与 iOS 核心链路，确认消息送达状态和工具事件合并缺口；测试沙箱失败后发起提权重跑。
- 连接器 74 项现有测试通过；用临时合成数据复现流式消息未完成时重载丢正文，并测量完整消息 JSON 重写成本；临时夹具已清理。
- 复核 Git 历史确认工具详情页“只展示命令”是近期主动简化，分析将区分产品取舍与协议数据遗漏。
- iOS 本轮检查范围是源码和测试覆盖阅读，未运行模拟器、真机或 APNs 端到端。
- 完成 docs/OPTIMIZATION-2026-09-12.md，给出优先级、代码入口、复现实验、工作量和迭代顺序；14 个本地文档链接检查通过，git diff --check 通过。业务代码未修改。

## 会话 1 — 2026-09-09
- 11:50 创建规划文件；抓取 vibelet.icu/zh 全文并整理为功能矩阵
- 11:52 读取 yukiTrace globals.css 设计 token（品牌色/分层/圆角/阴影）
- 下一步：下载 Vibelet 截图看实际 UI；读 yukiTrace 玻璃样式与 AGENTS.md
- 11:58 查看 Vibelet 5 张截图，记录 UI 结构与差异化机会到 findings.md
- 用户追加需求：规划+设计后编写 iOS 代码（ios/ 目录），为 android/miniprogram 预留多端结构 → 计划新增阶段 7/8
- 12:05 写完 docs/PRD.md、docs/DESIGN.md、shared/protocol.md；建立 ios/ android/ miniprogram/ design/ 目录
- 12:15 design/canvas/build.py 生成 10 块画板（9 屏 390×844 + 设计系统 1200×1180）；Chrome 无头截图自查，修复设备页重叠与审批卡换行 bug
- 12:18 画布组装并通过检查，准备发布 Claude Design 画布
- 12:30 设计画布已发布：https://claude.ai/code/artifact/d168c7db-23fa-426c-ad13-2b5bce984f41
- 12:45 ios/ 写完 21 个 Swift 文件（Package.swift + YzVibeKit 库 + App 壳 + XcodeGen project.yml + 单测），开始 xcodebuild 验证
- 12:55 iOS 26.5 模拟器运行时未安装 → 改用 SwiftPM 交叉编译（--triple arm64-apple-ios17.0-simulator）：库 + 测试目标编译通过，App 壳 typecheck 通过；修掉 3 条 Swift 6 迁移警告
- 13:00 写根 README.md；全部阶段完成

## 下一步（M2）
- 安装 iOS 模拟器运行时后跑 `swift test` / xcodegen 生成工程在模拟器上看真实玻璃效果
- 写 connector/（Node.js CLI：`npx yzvibe`），按 shared/protocol.md 实现 REST + WS
- Android / 小程序按 docs/DESIGN.md §6 映射实现

## 会话 2 — 2026-09-09
- git init + .gitignore + remote origin=git@github.com:yzstory/yzvibe-app.git（仓库为空）
- 自检结论：缺服务端。新增 connector/（Node.js）：REST + WS、一次性配对二维码、~/.yzvibe 持久化、Claude Code stream-json 驱动、MCP 审批桥（--permission-prompt-tool）、Mock Agent、Cloudflare Tunnel、文件只读 API、上传；`npm test` 端到端通过
- iOS 对接修正：容错解码（连接器 JSON 缺字段/未知枚举）、Device.id=connectorId、设备持久化 + 钥匙串、AppStore.live() 真实客户端、消息/审批懒加载、session.created 事件、本地通知、PhotosPicker 上传、文件 API 带 sessionId；干净重编译 20 文件通过
- shared/protocol.md 同步新增端点（/approvals、/sessions/:id/stop、上传方式、鉴权、审批实现说明）
- 中文 README（根 + connector/）；提交并 push 到 origin/main
- 端口：9876 被 Vibelet 自己的连接器（~/.vibelet/runtime，PID 55599）长期占用 → YzVibe 默认改 19876，连接器 EADDRINUSE 时自动后移最多 20 个端口，二维码携带实际端口；iOS 默认端口同步；新增回退测试；本机 smoke 启动通过
- 真机首跑（用户 iPhone + 真实 Claude）反馈修复：助手气泡 Markdown 渲染（MarkdownText）、会话标题随首条消息更新（connector 推 session.updated + 本地即时更新）、composer 渐变底避免透出、流式增量自动滚底、聊天页隐藏 Tab 栏、键盘三种收起方式（滚动/点消息区/键盘工具栏「收起」）

## 2026-09-09 会话选项（模式 / 模型 / 思考强度）
- iOS 打包报 Signing 需要 team：project.yml 加 `DEVELOPMENT_TEAM: TRVTR5HQP8` + `CODE_SIGN_STYLE: Automatic`，xcodegen 重新生成，真机 generic 构建通过
- 连接器：新增 `agents/options.js`（Plan/Normal/Trust、模型、effort 在 Claude / Codex 上的参数映射 + `GET /agents` 能力表，Codex 模型目录来自 `codex debug models`）、`agents/codex.js`（`codex exec --json` 每轮一进程，`exec resume` 续聊）、`PATCH /sessions/:id` 与 WS `session.configure`；Claude 驱动空闲时 `--resume` 重启带新参数；`ExitPlanMode` 变成低风险审批，批准后会话自动回 Normal
- iOS：Session/NewSessionRequest 加 mode/model/effort（去掉 yolo），`AgentCapabilities` + 内置回退表，聊天输入条改为「文本框 + 底部一排：相机 / 模式 / 模型 / 强度 / 发送」，新建会话页用分段选模式并显示该 Agent 的解释与参数；自定义模型与每个 Agent 上次用的选项存在 Settings
- 验证：connector 6 个测试通过；YzVibeKit 模拟器编译通过 + 单测；真实 Claude（haiku, trust→normal + effort 切换触发 --resume 重启）与真实 Codex（gpt-5.6-sol, normal→plan resume）各两轮冒烟均记得上下文
- 已知限制：Codex 非交互模式没有审批回调，Normal 只靠 workspace-write 沙箱兜底；要做 Codex 审批需改走 `codex app-server` 协议
- 新建会话页对齐 Vibelet（以远程 Plan/Normal/Trust 选项模型为基线叠加）：工作目录「浏览/收藏」、首句消息「历史/模板」、会话模式四张卡（继续上次 / 模式 / 模型 / 思考强度）、启动摘要卡；新增目录选择器（上级目录 / 主目录 / 新建文件夹 / 选择此文件夹）；连接器新增 /fs/dirs、/fs/mkdir 并加测试。Fast mode 未做：本机 claude CLI 没有对应参数。

## 2026-09-10 用量面板 + 图片压缩
- 连接器：`agents/usage.js` 归一每轮 token（Claude result / Codex turn.completed），`Session.usage` 含本轮与累计；`quota.js` 用本机 OAuth token 调 `api/oauth/usage`（含 Fable 本周额度 `weekly_scoped`），失败退回 `rate_limit_event`；`GET /quota?agent=`
- iOS：导航栏环形表（上下文占比）→「上下文详情」面板：上下文进度条、账号剩余用量（5 小时 / 本周 / 本周 Fable，含重置时间与来源）、本轮与累计 tokens、费用；图片上传前缩到 1568px JPEG
- 验证：connector 10 个测试、YzVibeKit 15 个测试

## 2026-09-10 终端会话导入 / 模型列表 / 去掉快捷回复
- 连接器 `transcripts.js`：列出 ~/.claude/projects 与 ~/.codex/sessions 里的会话（标题、cwd、分支、来源），手机打开时解析 transcript 接管，之后 --resume 续聊；Codex 额度从 rollout 的 token_count.rate_limits 取
- Claude 预置模型改为带版本的完整 ID：claude-fable-5-1 / claude-opus-5 / claude-sonnet-5 / claude-haiku-4-5-20251001（Haiku 5 尚不存在）
- iOS：会话卡显示「终端 / SDK」来源与 git 分支，「我」页可关闭终端会话显示；「模型列表」编辑器按 Agent 增删改模型 ID 与显示名，可恢复默认；聊天页去掉快捷回复
- 验证：connector 11 个测试，YzVibeKit 18 个测试

## 2026-09-10 图片：先选后发、气泡缩略图、全屏查看
- iOS：选图后进入输入条上方的待发送区（最多 6 张，可删），可配文字一起发；用户气泡显示缩略图，点开全屏（双指缩放、双击、分享）；附件从连接器 /uploads/:id 拉取并缓存
- 连接器：只发图不带文字时不再给 Claude 空文本块（API 会拒绝）；Codex 用默认提示；上传索引可在重启后按 id 从磁盘找回
- 验证：真实 Claude 只发一张红色 PNG 问颜色回答「Red.」；connector 11 个测试、YzVibeKit 19 个测试、App 工程编译通过

## 2026-09-10 连接器后台运行 + 稳定性
- CLI 改为子命令：`yzvibe [start]` 后台启动并打印二维码后退出（终端可关）、`run` 前台、`stop` / `restart` / `status` / `qr` / `logs [-f]`、`install` / `uninstall`（macOS launchd KeepAlive / Linux systemd --user，开机自启、崩溃拉起）。实例信息写 `~/.yzvibe/daemon.json`（0600，含内部 secret），日志 `~/.yzvibe/yzvibe.log`（>5MB 轮转）
- 新增 `GET /internal/status`（secret 鉴权）：CLI 取配对码 / 统计；修复配对码过期后永远无法再配对的 bug（`Pairing.current()` 过期即换新）
- Cloudflare 临时隧道断开自动重连并重新公告（实测 kill cloudflared 后 12 秒换到新地址）；SIGHUP 也走优雅退出；启动时清理上次残留的 mcp-*.json
- 验证：connector 13 个测试（新增配对码过期、后台守护端到端）；本机实测 local / tunnel 两种模式的 start / status / qr / logs / restart / stop

## 2026-09-10 配对三通道 + 相册扫码修复
- iOS 修 bug：扫码页右上角「相册」按钮之前是空 action（`circleButton("photo") {}`），换成 `PhotosPicker` + `QRImageScanner`（CIDetector，后台线程解码，识别不到时放大一倍重试）
- 连接器新增公开路由 `GET /pair?token=`（手机浏览器落地页，自动跳 `yzvibe://` 唤起 App，附「打开 App」按钮与可复制 JSON）与 `GET /pair.json?token=`；查看不消费配对码，错误 / 过期返回 410
- `yzvibe qr` 一次给出二维码 + 外链 + JSON 配置，`--link` / `--json` 只输出一项
- iOS `PairingPayload(text:)` 通吃深链 / 外链 / JSON / 夹在说明文字里的任意一种；「手动添加」页加「粘贴配置」卡（可从剪贴板一键粘贴并自动填字段）
- `RootTabView.onOpenURL` 处理 `yzvibe://pair?…`，浏览器唤起后自动配对并跳到设备页（`yzvibe` scheme 早已在 project.yml 注册）
- 验证：connector 15 个测试通过（新增落地页 / JSON / 过期失效 / relay 拼链 2 组）；YzVibeKit 与测试目标交叉编译通过，新增 5 个解析与二维码识别测试（本机无 iOS 模拟器运行时，未能实跑）；落地页在 127.0.0.1 与局域网地址实测 HTTP 200，深链与 HTML 转义正确
- 已知环境问题：本机 Clash Party 代理对新分配的 trycloudflare 域名经常握手失败（curl HTTP 000），同一时刻 Vibelet 的长期隧道正常；origin 本身没问题，手机走自己的 DNS 一般可达，实在不通就 `yzvibe restart --access=local` 走局域网

## 2026-09-10 聊天输出与远程文件（对齐 Vibelet 截图）
- 代码块：`CodeBlock` 加语言标签 + 「复制」按钮（复制后 1.6 秒回落），内容可横向滚动、可选中；聊天里的围栏代码块自动带语言名
- 聊天正文里的文件路径变成可点链接：`FilePathDetector` 判断行内代码像不像路径（命令 / 参数 / URL / `and/or` 都排除，点文件与目录都认，剥离中英文收尾标点），`MarkdownText.linkifyPaths` 给它套 `yzfile://` 链接，由 `OpenURLAction` 拦截 → 打开文件查看器
- 新增 `FileViewerView`：标题=文件名、副标题=完整路径（主目录缩成 `~`）、大小 / 修改时间 / 「工作目录外」标记，右上角「下载」与「复制」；文本走 CodeBlock，图片直接显示，>2MB 提示改用下载；下载写临时文件后走系统分享面板（存到「文件」App / 隔空投送）
- `FilesView` 改成点文件进查看器（原来的「下载到手机」只弹 toast，是假的），列表长按可复制路径
- 连接器：新增 `GET /files/stat`；`preview` / `download` 换用 `resolveReadable`——工作目录内放行，目录外只放行主目录里的非敏感文件（私钥 / 凭据 / keychain 等一律 403），download 补 content-length
- 多段气泡输出本来就有（连接器在工具调用前后切分 assistant 消息），无需改动
- 验证：connector 17 个测试通过（新增权限矩阵与 stat/download 两组）；iOS 新增 4 个测试并编译通过，另把 `FilePathDetector` 抽出来在 macOS 上真跑了 27 条用例全过；对运行中的连接器做了端到端实测：工作目录内 / 工作目录外 `~/.yzvibe/pairing.txt` 均 200 并成功下载，`~/.ssh/id_rsa` 与 `../../etc/passwd` 均 403

## 会话 3 — 2026-09-10：评估后的 7 项改进
1. 远程推送：connector/src/push.js 直连 APNs（ES256 JWT + HTTP/2），环境自动回退、失效 token 清理；iOS PushCenter + AppDelegate + entitlements；审批 time-sensitive、回复仅在手机离线时推、审批解决发静默推送更新角标
2. 断线重同步：scenePhase 触发 resync，GET /sync 一次拿全，消息按服务端游标增量补，本地乐观消息用 isLocal 标记去重；WS 30 秒心跳 + 立即重连
3. 工具输出可见：连接器捕获 tool_result 内容与 Edit/Write 的行级 diff（src/diff.js），工具卡按消息气泡归属；iOS 工具卡可展开，diff 按 +/- 着色
4. 审批规则：src/rules.js（tool/prefix/exact × session/global × TTL），审批卡「总是允许…」，自动放行留系统消息，「我 › 安全 › 审批规则」可撤销
5. 资源回收：Claude 进程空闲 15 分钟回收（--resume 接回）、上传 14 天 / 关闭会话 45 天 / 孤儿文件定期清理、yzvibe devices / revoke
6. 测试落地：ClaudeStreamTranslator 可用录制事件流测试；连接器 36 项、iOS 36 项（装了 iOS 26.5 模拟器运行时后真跑）；.github/workflows/ci.yml
7. 分发：npm 包就绪（files/prepublishOnly/npm pack 验证 54.7kB）、ios/scripts/archive.sh 归档并可直传 TestFlight

## 会话 3 追加（用户 2026-09-10 追加的 6 项）
8. 消息队列：连接器侧 session.queue，忙时排队、本轮结束自动接上、可取消；`mode=now` 插队并 SIGINT 打断当前轮。
   实测：Claude Code 的 stream-json 输入本身不排队（多写一条只是下一轮），也没有中断控制消息，所以队列与可见状态由连接器做。
9. 地址自愈：/health 与配对配置带 endpoints（隧道/Tailscale/局域网）；手机主地址失败时按 connectorId 探活切换；
   启动与隧道重连时静默推送新地址；同一 Wi-Fi 下 Bonjour 广播 _yzvibe._tcp。电脑重启 / 隧道换地址不再需要重新扫码。
10. 会话改动视图：GET /sessions/:id/diff（git status + diff，新文件给全文，scope=session 跟基线 commit 比）；
    iOS SessionDiffView 按文件折叠、+/- 着色。
11. Live Activity / 灵动岛：SessionActivityAttributes + WidgetKit 扩展；活动 token 交给连接器，
    锁屏时由 APNs liveactivity 推送更新（Date 必须用 Swift 默认编码，测试里已固定这一点）。
12. 斜杠命令：清单以 Claude 在 system.init 上报的 slash_commands 为准（实测 64 个里仅 3 个终端专用），
    手机端命令（/new /diff /files /usage /stop…）就地执行；Codex exec 不解析斜杠命令，已在面板上标明。
13. Skill：扫 ~/.claude/skills（符号链接要用 statSync）、项目 .claude/skills、插件 installPath，以及 ~/.codex/skills。
    修了两个 bug：符号链接目录被漏掉、frontmatter 描述超过 8KB 被截断。
- 测试：连接器 41 项、iOS 45 项，全部在模拟器上实跑通过。

## 会话 4 — 2026-09-11：视觉重构（方向 B「焦橙纸感」）
先做了 4 个方向对比（`design/directions/`，浏览器打开 index.html），用户选定 B：**结构全部还给系统，品牌只留一个焦橙 + 一层暖纸**。

- 色板重写：hex 直接定义（上一版 oklch 换算让文档 `#C2573A` 与实际渲染 `#DE602F` 差了一档、深色底比设计意图暗一档）。
  主色 `#C75015`（白字 4.58:1），胶囊文字 `#A63D02`，暖纸底 `#F9F6F2`，深色 `#201E1B`。新增 `lightHighContrast` / `darkHighContrast`，跟随系统「增强对比度」。
  修掉的不达标项：主按钮白字 3.50→4.58、时间戳 2.69→3.69、brand 胶囊 2.97→5.30、amber 1.64→3.58。
- 结构：删掉自绘的 `PageScaffold`（原来 `.toolbar(.hidden, for: .navigationBar)` 自己画大标题），四个 Tab 全换成
  `NavigationStack` + `.navigationTitle` + `.searchable` + `List`。会话 / 审批 / 设备用 `.plain` + 纸卡行，
  设置 / 文件 / 规则 / 模型用 `.insetGrouped`，新建会话与手动添加改成 `Form`。空态一律 `ContentUnavailableView`。
  由此拿到了侧滑（停止 / 复制路径 / 撤销规则 / 移除设备）、系统分组与刷新。
- 动态字体：43 处写死的 `.system(size:)` 换成系统文本样式，固定尺寸控件改用 `@ScaledMetric`。
- 装饰球删除（`AmbientBackground` 只剩暖纸底），玻璃只留输入条 / Toast / 配对遮罩 / 扫码框，并处理 `reduceTransparency`。
- 修的 bug：`RootTabView` 的 `.tint` 写死 light 色板，深色模式取错色；`ModelListEditorView` 的 `.swipeActions`
  挂在 List 之外从来没生效；「仅活跃」在设置页和会话页各有一份互不相干的状态，现在统一到 `settings.activeOnly`。
- 新增 `PaletteContrastTests`：四套色板 × 15 组前景/背景断言，把「改颜色」和「掉到不合规」绑在一起。
- 同步：docs/DESIGN.md 重写，design/canvas 的 token 与材质跟到 B（各屏版式仍是画稿期的自绘导航，以代码为准）。
- 验证：iOS 按 arm64-apple-ios17.0-simulator 交叉编译通过（含测试目标）；连接器 46 项测试通过。
  未在模拟器实跑 —— 本机没装 iOS 运行时，XCTest 由 CI 执行。

## 会话 8：审批增强进行中
已核验现有规则链路及 Codex 不返回建议的原因；准备服务端 Trust 专用操作与 iOS 共用审批卡入口。读取时引用不存在的 approvals.js 和一次计划补丁上下文不匹配，均已改为真实文件位置。

审批实现完成：Codex 文件修改规则、复杂命令完整匹配、规则原子保存与失败保留审批、单请求 Trust 切换及当前/后续权限放行。连接器 97 项通过；当前工作区 iOS 117 项通过（含并行语音输入测试），其中新增审批 3 项。首次审批测试夹具缺 header 已修正；首次失败退出期间出现既有网络测试 URLSession teardown 重连异常，完整重跑成功。准备独立提交审批文件并检查 CI。

## 2026-09-13 通知修复
- 已完成整轮 final 通知、每手机通知开关持久化/同步、去重和离线同步提示；不改变聊天多段输出。
- iOS 118 项通过（53 XCTest + 65 Swift Testing），包含工作区并行语音测试；日志 /tmp/yzvibe-notification-ios-tests-r3.log。
- 连接器 103 项全量测试通过；日志 /tmp/yz-notification-node-final.log。
- 通知修复 33dfb94 已 push；GitHub CI 34728876242 全部通过，工作区语音输入改动保留。尚未上传包含通知修复的 TestFlight 构建。

## 2026-09-14 Android 实施开始
用户确认全部兼容计划。保留既有改动，Android 独立新增；不发布未验证的厂商推送承诺。

### Android 首版验证
- assembleDebug / testDebugUnitTest / lintDebug 通过；9 项单元测试覆盖协议和 HTTP 边界。
- API 35 模拟器实际配对独立 mock 连接器，验证会话切换及进程重启后的草稿恢复、可靠投递、流式回复、审批允许、渲染后的 Markdown 预览。
- 自动测试发现并修复连续回复未跟随最新位置的问题；同时保留手动离开底部后不自动跳回。
- 新增 android/tools/smoke.py，可在隔离模拟器重复执行；不启动真实 Agent、不读取真实会话。
- APK 为 debug 签名首版内部联调包；未提交商店、未 push、未修改 iOS 或重启用户连接器。
- 国内厂商后台推送仍待品牌/凭据，当前不能宣称锁屏审批可达；其余差异见 android/README.md。

### 2026-09-15 手机历史缓存与渲染优化
- iOS：新增 actor 磁盘历史缓存（100 MB LRU）；缓存优先展示、重连仅刷新当前会话、其余进入时校准；写入合并并跳过未完整加载的历史。初始渲染最近 80 条，较早消息按需展开；Markdown 解析有界缓存。
- Android：新增同预算 IO 磁盘缓存；完整快照标记控制重复进入请求，断线后重新校准；保留既有草稿/发送队列存储。
- 验证：iOS 模拟器 144 项测试通过（含 4 项新缓存/重连测试）；Android 11 项单测、assembleDebug、lintDebug 通过。未执行 push、发布或连接器重启。

### 2026-09-15 TestFlight Build 34
- 用户授权发布：当前 iOS 源码归档为 0.1.0（34），主 App 与 Widget 构建号一致。
- 使用共享 App Store Connect API 密钥及 `testFlightInternalTestingOnly=true` 上传，09:06:12 日志确认 `Upload succeeded`、`EXPORT SUCCEEDED`。
- 归档保留于 `ios/build/YzVibe-build34.xcarchive`，上传日志 `/tmp/yzvibe-build34-upload.log`。按用户既有要求，上传成功后停止，不等待 Apple 后续处理；本轮未 push 或重启连接器。

## 2026-09-15 跨端功能对齐（进行中）
用户要求一次完成 HTML 双端预览与 Android 设备/会话/详情缺口。保留上一轮 Android 未提交的视觉改动；本轮不自动发布。
- 安卓第一轮 native 详情及工具聚合编译通过；iOS HTML 实现完整 App 模拟器编译通过。
- Lint 发现 readNBytes 只支持 API 33，已替换为有上限的通用流读取。iOS 新 WebKit delegate 签名需要 @MainActor @Sendable，已修正。
- iOS 实际 WKWebView 渲染测试通过（相对 CSS、SVG、JS 与点击）；连接器全量 130/130 通过。
- Android 长回复首次定位末尾、80 项连续工具单卡折叠已通过并截图核验。测试截图遇到主窗口/弹层多个 root，改为采集最上层 root。
- 全量 iOS 测试暴露旧网络测试的全局回调保留 client，URLSession 已销毁后仍触发 socket 重连；修正该测试 teardown 清除回调，再运行全量。单独 HTML 用例已正常通过。
- Android 13 项单元测试、Lint（0 错误）通过；ParityFlowTest 在深色、浅色和 1.3 倍字体均通过。
- iOS 92 项全量测试通过，完整 App 模拟器构建通过。旧缓存测试固定等待 30 ms 在并行 UI 测试下不稳定，改为有上限地等待真实回调。
- Compose captureToImage 对 Material sheet 取到了底层 Activity window；改用系统合成截图，重新采集最终页面图（功能断言不受影响）。

### 双端预览与 Android 对齐：最终验收
- Connector 全量 130 项、iOS 全量 92 项、Android 单元测试 13 项通过；iOS App/Widget 模拟器构建通过，Android APK 构建及 Lint 通过（0 errors、15 warnings）。
- ParityFlowTest 在深色、浅色、1.3 倍字体三组均通过，产出 27 张系统窗口截图；逐项核对 HTML 交互、上下文卡片、彩色 diff、交付记录、配置与诊断，以及长会话与工具分组。
- 截图改为系统窗口捕获，避免 Compose 根节点截图漏掉底部弹层。
- HTML 预览需要同时更新桌面连接器与移动客户端；仅支持 HTML 所在目录内的静态资源，外部 CDN/API 不开放。本轮未上传 TestFlight 或发布连接器。

### iOS build 36 发布完成
- 用户授权先发布 iOS；App/Widget 版本升至 36，Release 归档与上传成功。
- Apple API 确认 VALID / IN_BETA_TESTING，内部测试可更新；发布说明见 docs/RELEASE-0.1.0-36.md。

### iOS build 37：日常开屏优化与上传
- 冷启动约 1.5 秒、首次约 1.9 秒；前台计时、后台取消、通知与配对跳过、恢复不重播。
- Release 归档及版本检查通过，2026-09-15 22:11:06 上传成功；按用户要求停止于 Upload succeeded，不等待 Apple 处理。

### 2026-09-15 Android：安装官方 Android skills 并按其优化
- 用户要求只在本项目安装 https://github.com/android/skills 并据此优化安卓端、尽量复刻 iOS。24 个官方 skill 复制到 `.claude/skills/<name>/`（Claude Code 的项目级 skills 目录，附 Apache-2.0 LICENSE），不装到全局。本轮实际用到 edge-to-edge、adaptive、navigation-event 三个。
- 边到边（edge-to-edge skill）：`enableEdgeToEdge()` + `isNavigationBarContrastEnforced = false`；`styles.xml` 不再写死 `statusBarColor` / `navigationBarColor`，系统栏图标明暗由 `YzTheme` 按应用内「外观」决定（enableEdgeToEdge 自己的判断只看系统深色模式，应用内覆盖时会对不上）。列表统一改 `contentPadding` 让位；输入条用 `safeDrawing` 底部并集同时覆盖导航栏与输入法，去掉会重复加边距的 `imePadding`。开场全屏 Dialog 补 `decorFitsSystemWindows = false`。
- 自适应（adaptive skill Step 1/2/4）：`Scaffold + NavigationBar` 换成 `NavigationSuiteScaffold`，宽窗口自动切侧边导航栏；会话内与键盘弹出时用 `NavigationSuiteType.None` 隐藏导航区（该版本还没有 `NavigationSuiteScaffoldState`）。设备与会话列表换 `LazyVerticalGrid` + `GridCells.Adaptive`，分组头 `GridItemSpan(maxLineSpan)` 占整行。新增 `ui/Previews.kt` 四档形态因子预览。未做列表-详情双栏：`ListDetailSceneStrategy` 以 Navigation 3 为前置，迁移范围超出本轮，已记进 android/README.md 的边界清单。
- 预测式返回：会话页 `BackHandler` 换成 `PredictiveBackHandler`，手势进度驱动缩放 / 位移 / 淡出 / 圆角，松手取消回弹。没用 navigation-event skill 的 `androidx.navigationevent`，因为它要 compileSdk 36（本机只装了 Platform 35）且本应用未用 Navigation 3；已在 README 记下这处偏离。
- iOS 对齐补齐：四套色板（浅 / 深 × 标准 / 高对比度）与 `Accents`（琥珀 / 鼠尾草 / 紫 / 蓝）对齐 iOS `Palette`；「外观」自动 / 浅色 / 深色；顶部胶囊 Toast 接管一过性提示（`report` 走 Toast、`fail` 才弹对话框）；「我」页补按目录分组 / 只看近七天 / 显示终端会话，与会话页共用 `Preferences`；中风险审批和用量仪表中档改用琥珀，不再和品牌橙混用。
- 验证：`assembleDebug` + 13 项单元测试 + `lintDebug`（0 error）通过；API 35 模拟器上 `DesignFlowTest`、`ParityFlowTest` 各自通过。实机核对了浅色 / 深色、输入法顶起输入条、2560×1600 下的侧边栏与三列网格、返回手势中途的缩放帧。
- 踩坑：mock 连接器的配对 token 一次性，手工冒烟用掉后跑联调测试会卡在第一个 `await`；`adb shell am start -d` 传含 `&` 的深链要在设备端 shell 里加引号，否则 token 被截断。两条都写进了 android/README.md。

### 项目发布体系与 deploy skill
- 新增本地 .agents/skills/deploy，Claude 入口软链至同一文件；精确 Git 忽略，不安装全局。
- docs/RELEASING.md 记录四渠道、独立 npm 版本、共享移动 build、产物证据及发布边界。Android versionCode 从1同步37，未重新分发包。
- mobile_version.py 在临时夹具验证版本不一致、同步、升版和降级拒绝；quick_validate 通过（系统 Python 缺 PyYAML，使用临时 venv）。官网7文件白名单打包通过；Git 忽略与 diff --check 通过。
- 网站旧/新域名不一致，当前 TLS 查询未取得站点有效响应，未宣称线上验证通过；skill 要求实际部署时核对。没有执行发布、push 或重启。

### 官网双端更新已发布
- 安卓二维码解码并链接至蒲公英 youzivibe，保留原始图片用于扫码；文案精简至3节，删除过时版本说明。
- 重新构建并截图 iOS 会话/聊天与 Android 审批；Android三种配置回归通过。CUA验证桌面和390px布局、复制、图集及下载页。
- static-only原子发布20260915-230947，保留旧版20260914-164657；线上8文件HTTPS200与SHA一致，404及HTTP308通过，无服务重启。
- 本地8765端口被占用，改用8767预览；旧服务未动。截图与源码在工作区，未push。

### 0.2.0 首版双端打包
- iOS App/Widget 与 Android 同步 0.2.0 (38)，包内版本校验一致。Android Debug 构建/单测/Lint与iOS Release归档通过。
- APK保存到android/app/build/outputs/releases/YzVibe-0.2.0-38-debug.apk。
- iOS于2026-09-15 23:18:39上传success；未等待Apple处理，未发布其他渠道。

### 0.2.0 (39) 设备页指南与版本
- 双端新增品牌官网指引、包内App版本与每设备真实连接器版本，统一build39。
- 安卓构建/单测/Lint、iOS Release归档与包内版本校验通过；23:32:16 iOS上传success，不等后续处理。
