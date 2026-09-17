# Connector 0.1.6

- 修复 Codex 账号额度：优先通过 App Server 的 account/rateLimits/read 查询实时通用额度。
- 历史回退排除 Spark 独立额度，使用事件时间而非文件修改时间；缺失数值不补成 0%。
- 对比 npm 0.1.5：运行时代码仅 src/quota.js、src/transcripts.js 变化，另更新包版本。
- 源码 HEAD：bf804dddfd87c85b231d7a8a3f8291ec804fb838 + dirty 工作区（打包时尚未提交）；随后随本发布记录提交。
- 验证：138 项测试通过，git diff --check 通过；npm pack 白名单核对通过，共 40 文件。
- 发布产物：yzvibe-0.1.6.tgz；SHA256：d5f16d1aed1b928b29b64ba9b328056080d23b6f476476245abb3590633a1379。
- 2026-09-17 22:44 CST，npm publish 退出码 0，回执 + yzvibe@0.1.6；npm 提示正在处理。
- 首次查询 registry 尚未同步：精确版本 404，latest 仍为 0.1.5；不重复上传。
- 未重启现有连接器。registry 同步后，在任务结束时执行 npx yzvibe@latest restart 升级。
- 后续核验：npm registry 的 latest 已同步为 0.1.6。
