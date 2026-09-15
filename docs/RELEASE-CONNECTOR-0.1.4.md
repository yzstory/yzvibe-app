# 连接器 0.1.4

- 新增 `/files/web-preview`，为移动端 HTML 预览提供经过认证的本地静态资源。
- 修复 npx 的 PATH 注入可能导致使用过期 Agent CLI 的问题。
- 修正端口回退测试的并发端口假设，确保失败时清理服务器。

发布前 134 项测试全部通过。npm publish 退出码 0，返回 `+ yzvibe@0.1.4`；npm 提示包正在处理，最终查询 latest 仍为 0.1.3，等待 registry 同步。未重启用户正在运行的连接器。

包 SHA-1：`80339b42882f28e2bd8ed4bc21be1949c274c000`。

版本可用后，任务结束时执行 `npx yzvibe@latest restart`，使现有进程使用新版。该命令会中断正在执行的任务。
