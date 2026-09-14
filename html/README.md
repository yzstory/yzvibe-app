# 柚子Vibe 静态介绍页

线上地址：https://vibe.aiyuki.cc/

原生 HTML / CSS / JavaScript，无构建依赖、外部字体或追踪脚本。布局参考 OpenAI 产品文章的标题、留白、窄正文与宽幅图片节奏，使用 柚子Vibe 品牌素材。

## 本地预览

在仓库根目录运行 `python3 -m http.server 8765 --bind 127.0.0.1 --directory html`，访问 http://127.0.0.1:8765。

## 打包

运行 `python3 html/build.py`。产物为 `html/dist/yzvibe-site.tar.gz` 和对应 SHA256 文件。打包使用固定白名单，只包含页面、样式、脚本及四张图片；部署配置、文档、服务器 skill 与证书不进入公开文件。

## 文件与交互

- `index.html`：介绍、截图、功能、安装入口及 SEO 元信息。
- `styles.css`：桌面三张截图与侧目录；小屏截图横向滚动及单栏正文；适配减少动态效果偏好。
- `app.js`：原生 dialog 图片预览（支持 Escape 与焦点恢复）、命令复制、目录高亮。
- `assets/`：2026-09-12 从 iPhone 17 Pro / iOS 26.5 模拟器截取的真实 App 演示数据画面；Logo 来自 `docs/assets/yzvibe-logo.png`，缩至 256px。
- `deploy/site.conf`：静态站点 nginx 配置，文档根目录 `/srv/yzvibe/current`。
- `deploy/edge.conf`：现有边缘 nginx 的域名 / HTTPS 路由片段。

实际服务器连接、部署和回滚说明保存在 `.claude/skills/test-server/`，该目录已加入 Git 忽略。证书和私钥不在项目中保存。

当前安装入口以仓库真实能力为准：连接器通过 npm / npx 启动，iOS 提供内部测试及 Xcode 源码构建，不提供尚未确认的 App Store / TestFlight 下载链接。
