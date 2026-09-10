import SwiftUI

/// App 入口：四个 Tab（设备 / 会话 / 审批 / 我）。iOS 26 的 TabView 自带液态玻璃浮动 Tab 栏。
public struct RootTabView: View {
    @State private var store: AppStore
    @State private var tab: Tab = .devices
    @State private var pairingFromLink = false
    @AppStorage("yz.appearance") private var appearanceRaw = Settings.Appearance.auto.rawValue

    public enum Tab: Hashable { case devices, sessions, approvals, me }

    public init(store: AppStore? = nil) {
        _store = State(initialValue: store ?? AppStore.live())
    }

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
            .tint(Palette.light.brand)
            .environment(store)
            .preferredColorScheme(Settings.Appearance(rawValue: appearanceRaw)?.colorScheme)
            .overlay(alignment: .top) { ToastView(text: $store.toast) }
            .overlay { if pairingFromLink { pairingOverlay } }
            // 手机浏览器打开连接器的 /pair 外链后，落地页跳到 yzvibe://pair?… 唤起这里
            .onOpenURL { url in Task { await handle(url) } }
            .task { await store.start() }
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
            .liquidGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                .padding(.horizontal, 18).padding(.vertical, 12)
                .liquidGlass(in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    withAnimation(Motion.quick) { self.text = nil }
                }
        }
    }
}

/// 通用页面容器：装饰球背景 + 大标题。
struct PageScaffold<Content: View, Trailing: View>: View {
    @Environment(\.palette) private var p
    let eyebrow: String
    let title: String
    var subtitle: String?
    let trailing: () -> Trailing
    let content: () -> Content

    init(eyebrow: String, title: String, subtitle: String? = nil,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
         @ViewBuilder content: @escaping () -> Content) {
        self.eyebrow = eyebrow; self.title = title; self.subtitle = subtitle; self.trailing = trailing; self.content = content
    }

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            Eyebrow(eyebrow, color: p.brand)
                            Text(title).font(.yzLargeTitle).foregroundStyle(p.label)
                            if let subtitle { Text(subtitle).font(.yzSubhead).foregroundStyle(p.labelSecondary) }
                        }
                        Spacer()
                        trailing()
                    }
                    .padding(.top, 8)
                    content()
                }
                .padding(.horizontal, Spacing.page)
                .padding(.bottom, 120)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
