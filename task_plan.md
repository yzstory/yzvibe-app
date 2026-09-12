# 任务计划：YzVibe — 参考 Vibelet 设计的「手机远程掌控桌面 AI 会话」App

## 目标
参考 vibelet.icu 的产品形态，设计一个同类 App（YzVibe）：
1. 深入研究 Vibelet 的功能、信息架构、交互流程
2. 产出产品规划文档（PRD / 信息架构 / 页面清单 / 技术方案草案）
3. 用 Claude Design 产出高保真视觉稿：Apple / iOS 26 液态玻璃（Liquid Glass）风格
4. 配色沿用上级目录 yukiTrace 的暖调 token（赭红 / 鼠尾草 / 琥珀 + 纸感分层）
5. 【用户追加】规划与设计完成后，按计划编写 iOS 代码，放在 ios/ 目录；未来会做 android/、miniprogram/ 等多端，都基于同一份 planning 与 design

## 阶段
- [x] 阶段 1：初始化规划文件（task_plan / findings / progress）
- [x] 阶段 2：研究 Vibelet（文案、截图、功能矩阵、连接方式、FAQ）→ 写入 findings.md
- [x] 阶段 3：研究 yukiTrace 设计系统（globals.css token、玻璃样式、AGENTS.md 设计原则）→ 写入 findings.md
- [x] 阶段 4：产出产品规划文档 docs/PRD.md（定位、用户、功能矩阵、信息架构、页面流、技术方案）
- [x] 阶段 5：产出设计规范 docs/DESIGN.md（液态玻璃 token、配色映射、组件规范）
- [x] 阶段 6：Claude Design 画布 — 10 块画板已发布 https://claude.ai/code/artifact/d168c7db-23fa-426c-ad13-2b5bce984f41
- [x] 阶段 7：搭建多端目录结构（ios/ android/ miniprogram/ docs/ design/ shared/ 协议文档）
- [x] 阶段 8：编写 iOS SwiftUI 代码（21 个文件，SwiftPM 交叉编译 iOS 模拟器通过，测试目标可编译）（ios/YzVibe：设计 token、玻璃组件、5+ 核心屏、Mock 数据、连接协议层）
- [x] 阶段 9：汇总交付，更新 progress.md

## 关键决策
| 决策 | 选择 | 原因 |
|------|------|------|
| 产品名 | YzVibe | 目录名即产品名 |
| 视觉风格 | iOS 26 Liquid Glass | 用户明确要求 |
| 配色 | yukiTrace 暖调（brand 赭红 oklch(0.64 0.17 40) 等） | 用户要求参考 |
| 设计工具 | Claude Design（design skill 画布） | 用户要求 |
| iOS 技术栈 | SwiftUI + iOS 26（Liquid Glass API，`.glassEffect`），iOS 17 回落为材质模糊 | 原生玻璃效果，未来多端各自原生实现 |
| 目录结构 | 单仓多端：docs/ design/ shared/(协议) ios/ android/ miniprogram/ | 用户要求多端共用 planning/design |
| 导航结构 | 底部 Tab：设备 / 会话 / 审批 / 我 | 与 Vibelet 差异化，审批是核心场景 |

## 遇到的错误
| 错误 | 尝试次数 | 解决方案 |
|------|---------|---------|
| build.py 修补脚本因 `cd` 到已在的目录失败而未执行（&& 短路） | 1 | 直接在当前目录重跑，改用断言确认每处替换命中 |
| iOS 26.5 模拟器运行时未安装，xcodebuild 找不到 destination | 2 | 改用 `swift build --triple arm64-apple-ios17.0-simulator --sdk <iphonesimulator sdk>` 交叉编译；单测需先在 Xcode › Settings › Components 下载 iOS 模拟器运行时 |
| connector `npm test` 脚本 `node --test test/` 在 Node 25 报 MODULE_NOT_FOUND | 1 | 改为 `node --test test/*.test.js` |
| Approval 自定义 CodingKeys 含 approvalId 导致 Encodable 合成失败 | 1 | 手写 encode(to:) |
| Bash 工作目录残留在 ios/，规划文件写错位置 | 1 | 命令开头显式 cd 到仓库根 |
| xcode-select 指向 CLT，xcodebuild 报错 | 1 | /Applications/Xcode.app 存在；用 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 前缀调用 xcodebuild，不改全局设置 |

## 会话 2 追加阶段（2026-09-09）
- [x] 阶段 10：初始化 git，接入 remote git@github.com:yzstory/yzvibe-app.git
- [x] 阶段 11：自检与优化 —— 编写 connector/（Node.js 桌面连接器：REST + WS + 配对二维码 + Claude Code stream-json 驱动 + 审批 MCP 桥），并修正 iOS 端与服务端对接的缺口（设备持久化、tolerant 解码、审批拉取、消息懒加载、本地通知）
- [x] 阶段 12：中文 README，提交并 push

## 会话 3（2026-09-10）：评估后的 7 项改进，一次性完成
- [x] 1 远程推送：连接器直连 APNs（ES256 JWT + HTTP/2），审批/回复完成推送；iOS 注册 token、点击跳转
- [x] 2 前台恢复与断线重同步：scenePhase 触发 resync，消息按游标增量拉取，WS 立即重连 + 心跳
- [x] 3 工具输出可见：连接器捕获 tool_result 内容与 Edit diff，iOS 工具卡可展开
- [x] 4 审批规则：按工具/前缀/会话的持久化规则，审批卡上「总是允许」，我页可管理
- [x] 5 资源回收：Claude 进程空闲回收、上传与旧会话清理、设备撤销 CLI
- [x] 6 测试落地：Claude 事件流翻译器可测 + 夹具、iOS 模拟器运行时、GitHub Actions
- [x] 7 分发：npm 包就绪（files/prepublish/pack 验证）、iOS 归档脚本与 TestFlight 说明

## 会话 3 追加（用户 2026-09-10 追加）
- [x] 8 任务执行中再次发消息：默认排队（可见「排队中」），也可选择立即发送打断
- [x] 9 连接器地址稳定性：重启电脑 / cloudflared 抖动后不必重新扫码（多端点 + 推送下发新地址）
- [x] 10 会话 Diff 视图（工作目录的累计改动）
- [x] 11 Live Activity / 灵动岛显示会话状态
- [x] 12 会话里支持常用斜杠命令（/compact、/new 等，Claude 与 Codex 各自适配）
- [x] 13 会话里支持各自能读到的 skill / 自定义提示词

## 会话 5（2026-09-12）：当前项目优化与拓展分析
- [x] 14：恢复历史规划，检查仓库结构、文档、已有修复和测试入口
- [x] 15：检查当前消息、持久化、连接、Agent 和 iOS 交互链路，记录代码依据
- [x] 16：运行合适的现有检查，并对重要缺口做隔离验证
- [x] 17：产出按价值与成本排序的优化、拓展路线及验收建议

本轮范围：代码和产品分析；只更新分析文档，不实施业务功能、不发布。

本轮检查错误：连接器测试受沙箱 EPERM 限制（监听本地端口、主目录临时文件），通过正式提权请求重跑。

## 会话 6（2026-09-12）：P1 修复、交付卡、诊断与内部测试发布
- [x] 18：全部 P1：发送箱/幂等接收、附件完整性、前台重连补数、流式持久化恢复、请求大小与字段校验
- [x] 19：实现可追溯的任务交付卡及连接诊断页（含脱敏导出）
- [x] 20：连接器 84 项、iOS 91 项回归通过，完整 App/Widget Release 归档成功；网页/原生 UI 控制服务持续超时，未完成人工页面验证
- [x] 21：更新协议/发布说明，提交并 push 本项目所有改动
- [ ] 22：build 11 已归档并成功上传为内部测试专用（16:49:54）；Apple 处理完成与内测组可安装状态待核验（Computer Use 系统权限未完成）

用户明确授权本轮实现、提交、push 和 TestFlight 内部测试发布。沿用现有界面风格，保持命令详情简洁，执行结果在交付详情中核验。

本轮中间错误：首次 npm test 误在根目录执行（改为 connector）；Swift 缓存写入受限（正式提权重跑）；泛型函数内嵌 Failure 类型导致编译错误（提取顶层类型）；旧清理测试计数因新 journal 文件增加（清理旧会话时同时删除 journal）。

## 会话 7（2026-09-12）：认证核验与手动切换连接
- [x] 26：交付卡按所属轮次消息定位，避免上一轮完成卡停留在新任务底部；保留历史入口
- [x] 23：核验 HTTP / WS 设备 Token 认证并补充回归，展示认证状态
- [x] 24：诊断页与设备配置支持手动选择候选地址，校验身份/认证后切换，保留配对与会话
- [ ] 25：回归测试、更新说明，沿用授权提交 push 并上传新的 TestFlight 内部测试构建

阶段 25 当前状态：实现 f001c51 已 push；连接器 87 项、iOS 101 项与 GitHub CI 34688562856 全部通过；build 12 Release 归档成功。18:29 上传失败，原因是 Xcode Apple Accounts 列表为空，已请用户登录后继续上传。未将归档成功视为 TestFlight 发布完成。
