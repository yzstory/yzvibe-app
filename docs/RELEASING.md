# YzVibe 发布体系

## 版本与渠道

| 产物 | 版本规则 | 发布方式 | 成功标准 |
| --- | --- | --- | --- |
| iOS App / Widget | 共同 X.Y.Z (build) | Release archive → TestFlight internal only | 上传退出码 0，Upload succeeded；默认不等 Apple 处理 |
| Android APK | versionName=X.Y.Z，versionCode=同轮 iOS build | 当前交付 Debug 测试 APK | 编译、相关测试、Lint、包内版本检查通过；正式渠道另配签名 |
| npm 连接器 yzvibe | 独立 SemVer | npm access token → npm publish --tag latest | publish 成功；registry 可用与否单独注明 |
| 官网 | 时间戳 + Git SHA + 产物 SHA256 | html/build.py → 自有 nginx releases/current 原子切换 | HTTPS、资源与页面交互通过 |
| 文档 | Git commit | docs/ 与 README → GitHub | 目标分支 push 成功，相对链接与内容一致 |

## 移动端共同版本

`ios/project.yml` 为版本源，iOS App、Widget 和 Android 三者必须一致。当前源码已统一为 **0.1.0 (37)**，不代表 Android 新包已经分发。

每轮发布选一个大于已分配、已上传编号的 build。只先发一端也同时更新另一端源码；同轮补发另一端沿用相同编号。已发布包要改代码重发则开启下一轮，不能覆盖旧包。营销版本按产品变化递增，npm 不跟随移动端 build。

本地 deploy skill 提供版本同步与检查脚本。没有 skill 的克隆也可手动同步 `ios/project.yml` 两个目标的 CFBundleShortVersionString / CFBundleVersion 与 `android/app/build.gradle.kts` 的 versionName / versionCode，再生成 Xcode 工程；构建不依赖被忽略的 skill。

## 发布流程

1. 明确目标渠道，核对本地改动、远端已发布版本与本次差异。
2. 统一移动版本，核验 npm 是否实际需要升级；记录源 HEAD 与工作区是否有未提交改动。
3. 完成相应测试和产物检查；只打包公开白名单，不含凭据或运维资料。
4. 按指定渠道发布。全量且有新协议依赖时，顺序为连接器 → 移动端 → 官网与文档。
5. 将版本、时间、校验和、验证结果、回执和未完成状态写入 `docs/RELEASE-*.md`。

“规划发布”不会上传。“发布 iOS”不会附带 npm、官网或 Git push。已有授权不重复询问。发布连接器包不重启用户正在运行的服务。

## 官网与文档边界

官网是 `html/` 的8文件静态白名单；不是文档站。文档目前由 GitHub 展示，不存在独立在线文档构建流程。若以后建设文档站，应单独选公开内容、域名和构建器。

网站说明中存在新旧域名不一致，执行发布前须以有效 TLS 请求和服务器当前 nginx 配置核实入口。生产连接与回滚细节只存在本地被忽略的运维 skill 中，不能进入官网产物。

CI 目前只执行验证；Git push 不会自动发布 npm、TestFlight 或官网。Android 暂无正式签名和商店发布配置，Debug 测试包必须明确标注。

## 项目级 deploy skill

- Codex：`.agents/skills/deploy/SKILL.md`
- Claude Code：`.claude/skills/deploy` 指向同一份内容
- 两个入口均由 `.gitignore` 忽略，不安装到全局，也不会随 Git 克隆分发。
- 在本项目中使用 `$deploy`，例如“用 deploy 发布 iOS”“用 deploy 发布连接器”“用 deploy 更新官网和文档”。新会话可发现项目 skill，当前会话也可直接引用路径。

凭据保存在仓库外或进程环境。skill 只记录获取方式，不保存 token、私钥或签名密码。
