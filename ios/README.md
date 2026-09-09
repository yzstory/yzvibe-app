# YzVibe iOS

SwiftUI 实现，iOS 17+；iOS 26 自动启用 Liquid Glass（`glassEffect` / 玻璃 Tab 栏），低版本回落为材质模糊。

```
ios/
├─ Package.swift            # YzVibeKit：全部 UI / 模型 / 网络（可独立编译与测试）
├─ Sources/YzVibeKit/
│  ├─ Design/               # token（oklch → sRGB）、玻璃修饰器、按钮样式、通用组件
│  ├─ Models/               # 与 shared/protocol.md 对应的数据模型 + Mock 数据
│  ├─ Networking/           # ConnectorClient 协议、HTTP+WS 实现、Mock 实现、Keychain
│  ├─ Store/                # AppStore（@Observable）
│  └─ Features/             # Root / Devices / Sessions / Chat / Approvals / Files / Me
├─ Tests/YzVibeKitTests/
├─ App/YzVibe/              # 薄壳 App 目标
└─ project.yml              # XcodeGen 描述
```

## 运行
```bash
brew install xcodegen
cd ios && xcodegen generate && open YzVibe.xcodeproj
```
默认使用 `MockConnectorClient`（离线示例数据）。联调时在 `RootTabView(store:)` 传入
`AppStore(client: HTTPConnectorClient(tokenProvider: { TokenStore.shared.token(for: $0.id) }), seedMock: false)`。

## 只编译库 / 跑测试（无需生成工程）
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -scheme YzVibeKit -destination 'platform=iOS Simulator,name=iPhone 17' build test
```
