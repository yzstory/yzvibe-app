# Connector 0.1.5

- 修复对外版本写死：从 package.json 读取。
- 状态区分在线配对身份、历史配对记录、推送注册记录；同身份多连接去重，心跳清理失联连接。
- CLI 展示运行中版本与 CLI 版本，devices 展示在线状态。
- 源码：8d80a688b781afe5b054b248d75924a74f97102c + dirty 工作区，未创建提交。
- 验证：135 项测试通过；npm pack dry-run 40 个文件，均在发布白名单，包含 src/version.js。
- npm publish 退出码 0，回执 `+ yzvibe@0.1.5`（2026-09-15 23:58 CST）；npm 提示处理中。SHA1 a0f09d0543a76f49e11105c7ec860229c16abc7e。
- 使用用户授权的仓库外 token 配置发布成功；whoami 的 E401 不代表缺少实际发布权限。
- Registry latest 已确认 0.1.5；已下载 npm 官方 tarball 并核验 SHA1。SHA256：6f17668c18ca3f0207da651cd2630edcce4d70290e1b225160b8940480a1fded。
- 2026-09-16 00:01 CST 左右使用该下载包执行 restart，运行 PID 28443，/internal/status 验证版本 0.1.5，当前在线 0、历史配对 17（验证时快照）。
