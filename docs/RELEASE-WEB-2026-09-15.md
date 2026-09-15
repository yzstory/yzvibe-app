# 官网更新：双端介绍与 Android 下载

2026-09-15 官网 https://vibe.yzcloud.icu/ 已更新。

- 页面从长篇功能说明精简为工作随身、看见成果、安装连接三个部分。
- 新增 Android 下载按钮与用户提供的二维码，解码链接为 https://www.pgyer.com/youzivibe ，浏览器确认目标为柚子Vibe Android 下载页。
- 新截图：本轮构建的 iOS Debug 模拟器演示会话/聊天，以及 Android API35 DesignFlowTest 审批画面；使用隔离演示数据。
- 保留 iOS 内部 TestFlight / 源码安装说明，不提供未经确认的公开邀请链接。
- 公开资源白名单由7扩为8项，新增 assets/android-qr.jpg。

验证：iOS构建通过，Android构建及深/浅/大字体 DesignFlowTest 通过；浏览器核对桌面与390px手机布局、复制命令、截图放大及Escape关闭、下载跳转。HTTPS全部8资源200且SHA256一致，未知路径404、HTTP308。纯静态原子切换，未更改nginx/Compose或重启服务。

发布标识：20260915-230947；上一版：20260914-164657。
包SHA256：4f146463743ceda3cb1b7b70cc74c9c95774ffc8dbc1e129caf398755799900f。
源HEAD：8d80a68，包含未提交工作区改动；本轮未push源码。

## 23:41 截图替换

按用户要求，将第三张 Android 测试审批图替换为用户提供的 iOS 实机改动截图，使用 assets/changes.jpg 原图；标题与替代文本同步为“iOS · 看改动”。白名单仍为8文件，移除旧图引用。

发布版本20260915-234136，上一版20260915-230947；包SHA256：54d68ccea607a2585a74cb024187ef6b7258d5fe2c27c8151094dd71fa824557。线上首页与新图均HTTPS200且内容一致。静态原子发布，无服务重启。
