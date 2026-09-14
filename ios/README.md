# 柚子Vibe iOS

SwiftUI 实现，iOS 17+；iOS 26 自动启用 Liquid Glass（`glassEffect` / 玻璃 Tab 栏），低版本回落为材质模糊。

```
ios/
├─ Package.swift            # YzVibeKit：全部 UI / 模型 / 网络（可独立编译与测试）
├─ Sources/YzVibeKit/
│  ├─ Design/               # token（oklch → sRGB）、玻璃修饰器、按钮样式、通用组件
│  ├─ Models/               # 与 shared/protocol.md 对应的数据模型 + Mock 数据
│  ├─ Networking/           # ConnectorClient 协议、HTTP+WS 实现、Mock 实现、Keychain
│  ├─ Store/                # AppStore（@Observable）
│  ├─ Voice/                # Apple 端侧转写、按住说话、原生回复朗读
│  ├─ Push/                 # PushCenter + UIApplicationDelegate（APNs 注册与通知跳转）
│  └─ Features/             # Root / Devices / Sessions / Chat / Approvals / Files / Me
├─ Tests/YzVibeKitTests/
├─ Widgets/YzVibeWidgets/   # 锁屏 / 灵动岛实时活动（WidgetKit + ActivityKit）
├─ App/YzVibe/              # 薄壳 App 目标（含 YzVibe.entitlements：aps-environment）
├─ scripts/archive.sh       # 归档 + 导出 ipa（--upload 直传 TestFlight）
└─ project.yml              # XcodeGen 描述
```

## 当前功能与版本

iOS 0.1.0 (26) 已进入 TestFlight 内部测试，详见 [build 26](../docs/RELEASE-0.1.0-26.md)。新增 OMP 接入与手机模型配置、本地 Markdown / 图片 / 视频预览、会话品牌图标。最新交互包括星光工具菜单、思考力度分档滑条、原生文本选区与复制、按住说话（上滑取消）及回复朗读。

语音通过 Apple Speech 在端侧转写；设备或语言不支持时提示不可用，不回退到云端识别。识别结果进入草稿，用户确认后发送。回复朗读使用 AVSpeechSynthesizer，过滤代码、常见命令与日志，并与录音互斥。

新增 Claude、Codex、OMP 三种助手及原彩高清 PNG 图标；OMP 支持按电脑展示模型与 HTTPS 配置，回复中的 Markdown、图片和视频可在 App 内查看。详见 [OMP](../docs/OMP.md) 与 [文件预览](../docs/REMOTE-FILE-PREVIEW.md)。

## 运行
```bash
brew install xcodegen
cd ios && xcodegen generate && open YzVibe.xcodeproj
```
默认走真实连接器（`AppStore.live()`）。没有配对设备时，设备页可以点「先看看演示数据」用离线示例。

## 远程推送

`App/YzVibe/YzVibe.entitlements` 声明了 `aps-environment: development`——Xcode 装机用它，
通过 App Store Connect（含 TestFlight）分发时导出流程会换成 `production`。
电脑那端的密钥配置见 `../connector/README.md`「远程推送」。App 里「我 › 通知 › 远程推送」能逐项看到状态。

## 锁屏 / 灵动岛

`Widgets/YzVibeWidgets` 是个 WidgetKit 扩展，显示会话在跑什么、要不要你批、排了几条、上下文用了多少。
`SessionActivityAttributes` 放在 YzVibeKit 里，App 与扩展共用。活动用 `pushType: .token` 启动，
token 交给电脑后，锁屏时的更新由连接器直接推（见 `../connector/README.md`）。
在「我 › 通知 › 锁屏 / 灵动岛」里可以关掉。

## 发 TestFlight

```bash
ios/scripts/archive.sh            # 归档 + 导出 build/YzVibe.ipa
ios/scripts/archive.sh --upload   # 顺便上传（需要 ASC_KEY_ID / ASC_ISSUER_ID）
```

使用 Xcode 已登录账号上传内部测试构建，可直接使用 `scripts/ExportOptions-TestFlight.plist`，完整命令见 [build 11 发布说明](../docs/RELEASE-0.1.0-11.md)。

也可使用 App Store Connect 团队 API 密钥上传已有归档（不会重新构建）：

```bash
# 先在环境中设置 ASC_KEY_ID、ASC_ISSUER_ID，以及可选的 ASC_KEY_PATH
bash ios/scripts/upload-testflight.sh /path/to/YzVibe.xcarchive
```

命令在仓库根目录执行；将路径替换成实际归档路径。上传后仍需核对 Apple 处理状态与内部测试可用性，不重复上传已成功的构建号。

## 只编译库（无需生成工程）
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift build --package-path ios --build-tests --triple arm64-apple-ios17.0-simulator \
  --sdk "$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun --sdk iphonesimulator --show-sdk-path)"
```

## 跑单元测试

需要装好 iOS 模拟器运行时：`xcodebuild -downloadPlatform iOS`（几个 GB，只要一次）。

`ios/` 目录里如果已经 `xcodegen generate` 过，xcodebuild 会优先用那个工程（它的 YzVibeKit scheme 不含测试目标），
所以在一个只有 Package.swift 的目录里跑：

```bash
mkdir -p /tmp/yzkit && cd /tmp/yzkit \
  && ln -sfn "$OLDPWD/Package.swift" . && ln -sfn "$OLDPWD/Sources" . && ln -sfn "$OLDPWD/Tests" . \
  && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
     xcodebuild -scheme YzVibeKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

覆盖：oklch 颜色转换、配对链接 / JSON / 二维码解析、Markdown 与文件路径识别、会话选项与能力表、
用量与额度解码、图片压缩、工具输出与 diff 解码、审批建议与规则、推送载荷解析、断线重同步的消息合并。
