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
