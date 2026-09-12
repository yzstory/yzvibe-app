import SwiftUI

/// App 入口：四个 Tab（设备 / 会话 / 审批 / 我）。Tab 栏、导航栏、列表全部用系统组件，
/// 品牌只通过 `.tint` 和内容里的强调色出现。
public struct RootTabView: View {
    @State private var store: AppStore
    @State private var tab: Tab = .sessions
    @State private var pairingFromLink = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage("yz.appearance") private var appearanceRaw = Settings.Appearance.auto.rawValue

    public enum Tab: Hashable { case devices, sessions, approvals, me }

    public init(store: AppStore? = nil) {
        _store = State(initialValue: store ?? AppStore.live())
    }

    private var appearance: Settings.Appearance { Settings.Appearance(rawValue: appearanceRaw) ?? .auto }
    /// `.preferredColorScheme` 只作用于子树，这里要自己算出生效的模式，否则深色下 tint 会取错色板。
    private var effectiveScheme: ColorScheme { appearance.colorScheme ?? systemScheme }

    public var body: some View {
        PaletteProvider {
            TabView(selection: $tab) {
                DevicesView(onOpenSessions: { tab = .sessions })
                    .tabItem { Label("设备", systemImage: "desktopcomputer") }
                    .tag(Tab.devices)
                SessionsView()
                    .tabItem { Label("会话", systemImage: "bubble.left.and.text.bubble.right") }
                    .tag(Tab.sessions)
                ApprovalsView()
                    .tabItem { Label("审批", systemImage: "tray.full") }
                    .badge(store.pendingApprovals.count)
                    .tag(Tab.approvals)
                MeView()
                    .tabItem { Label("我", systemImage: "person.crop.circle") }
                    .tag(Tab.me)
            }
            .tint(Palette.current(effectiveScheme, contrast).brand)
            .environment(store)
            .preferredColorScheme(appearance.colorScheme)
            .overlay(alignment: .top) { ToastView(text: $store.toast) }
            .overlay { if pairingFromLink { pairingOverlay } }
            // 手机浏览器打开连接器的 /pair 外链后，落地页跳到 yzvibe://pair?… 唤起这里
            .onOpenURL { url in Task { await handle(url) } }
            // 回到前台：iOS 挂起 App 时 WebSocket 一定断了，这里立刻重连并把落下的消息补齐
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await store.resync() }
            }
            .onChange(of: store.pendingApprovals.count) { _, n in PushCenter.shared.setBadge(n) }
            .task {
                PushCenter.shared.onOpen = { payload in
                    switch payload.kind {
                    case .approval, .approvalResolved: tab = .approvals
                    case .reply:
                        tab = .sessions
                        if let sid = payload.sessionId { store.openSessionRequest = sid }
                    default: break
                    }
                    Task { await store.resync() }
                }
                await store.start()
            }
        }
    }

    private var pairingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text("正在配对…").font(.yzSubhead)
            }
            .padding(24)
            .liquidGlass(in: RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous))
        }
        .transition(.opacity)
    }

    /// 处理 `yzvibe://pair?…` 深链：直接配对并跳到设备页。
    private func handle(_ url: URL) async {
        guard let payload = PairingPayload(text: url.absoluteString) else {
            store.toast = "这不是有效的 YzVibe 配对链接"
            return
        }
        tab = .devices
        pairingFromLink = true
        defer { pairingFromLink = false }
        do { try await store.pair(payload) }
        catch { store.toast = "配对失败：\(error.localizedDescription)" }
    }
}

private extension Settings.Appearance {
    var colorScheme: ColorScheme? { switch self { case .auto: nil; case .light: .light; case .dark: .dark } }
}

/// 顶部玻璃 Toast，3 秒自动消失。
struct ToastView: View {
    @Environment(\.palette) private var p
    @Binding var text: String?
    var body: some View {
        if let text {
            Text(text)
                .font(.yzSubhead)
                .foregroundStyle(p.label)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .liquidGlass(in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityAddTraits(.isStaticText)
                .task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    withAnimation(Motion.quick) { self.text = nil }
                }
        }
    }
}

/// 页面统一背景：系统 List / ScrollView 之下的一层暖纸。
/// 大标题、搜索、工具栏一律交给各页自己的 `NavigationStack` + 系统修饰符，不再自绘。
struct PaperBackground: ViewModifier {
    @Environment(\.palette) private var p
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(p.surface.ignoresSafeArea())
    }
}

extension View {
    /// 给 List / ScrollView 换上暖纸底色（系统默认是冷灰）。
    func paperBackground() -> some View { modifier(PaperBackground()) }
}
