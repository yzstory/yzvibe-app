import SwiftUI

struct NewSessionView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State private var req = NewSessionRequest(cwd: MockData.recentFolders.first ?? "")
    @State private var firstMessage = ""
    @State private var busy = false
    @State private var seeded = false

    private var caps: AgentCapabilities { store.capabilities(for: req.agent, on: store.selectedDeviceId) }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        PaperCard {
                            VStack(alignment: .leading, spacing: 18) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Eyebrow("Agent")
                                    SegmentedPills(items: AgentKind.allCases.map { ($0, $0.displayName) }, selection: $req.agent)
                                }
                                VStack(alignment: .leading, spacing: 10) {
                                    Eyebrow("工作目录")
                                    HStack(spacing: 10) {
                                        Image(systemName: "folder").foregroundStyle(p.labelSecondary)
                                        TextField("~/project", text: $req.cwd).font(.yzMonoBody).textInputAutocapitalization(.never).autocorrectionDisabled()
                                    }
                                    .padding(.horizontal, 16).frame(height: 52)
                                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(p.fill).overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(p.border, lineWidth: 1)))
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(MockData.recentFolders, id: \.self) { f in
                                                Button { req.cwd = f } label: { Chip((f as NSString).lastPathComponent, tone: f == req.cwd ? .brand : .fill, mono: true) }.buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }
                                VStack(alignment: .leading, spacing: 10) {
                                    Eyebrow("首条消息（可选）")
                                    TextField("让 Agent 审查、修复或继续某件事，会话启动后自动发送", text: $firstMessage, axis: .vertical)
                                        .lineLimit(3...6)
                                        .font(.yzSubhead)
                                        .padding(14)
                                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(p.fill).overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(p.border, lineWidth: 1)))
                                }
                            }
                        }
                        SectionCard("会话模式") {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("接续上次会话").font(.yzHeadline).foregroundStyle(p.label)
                                    Text("恢复该目录最近的上下文").font(.yzFootnote).foregroundStyle(p.labelSecondary)
                                }
                                Spacer()
                                Toggle("", isOn: $req.continueLast).labelsHidden().tint(p.brand)
                            }
                            .padding(.horizontal, Spacing.card).frame(minHeight: 60)
                            Divider_()
                            VStack(alignment: .leading, spacing: 10) {
                                SegmentedPills(items: SessionMode.allCases.map { ($0, "\($0.displayName) · \($0.subtitle)") }, selection: $req.mode)
                                if let info = caps.modeInfo(req.mode) {
                                    Text(info.description).font(.yzFootnote).foregroundStyle(req.mode == .trust ? p.danger : p.labelSecondary)
                                    Text(info.flag).font(.yzCaption).monospaced().foregroundStyle(p.labelTertiary)
                                }
                            }
                            .padding(.horizontal, Spacing.card).padding(.vertical, 12)
                            Divider_()
                            HStack(spacing: 12) {
                                Text("模型").font(.yzHeadline).foregroundStyle(p.label)
                                Spacer()
                                ModelMenu(agent: req.agent, caps: caps, model: $req.model)
                            }
                            .padding(.horizontal, Spacing.card).frame(minHeight: 56)
                            Divider_()
                            HStack(spacing: 12) {
                                Text("思考强度").font(.yzHeadline).foregroundStyle(p.label)
                                Spacer()
                                EffortMenu(agent: req.agent, caps: caps, model: req.model, effort: $req.effort)
                            }
                            .padding(.horizontal, Spacing.card).frame(minHeight: 56)
                        }
                    }
                    .padding(Spacing.page)
                    .padding(.bottom, 80)
                }
            }
            .navigationTitle("新建会话")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if !seeded { seeded = true; applyDefaults() } }
            .onChange(of: req.agent) { _, _ in applyDefaults() }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button { Task { await start() } } label: {
                    if busy { ProgressView().tint(p.brandInk) } else { Label("开始会话", systemImage: "sparkles") }
                }
                .buttonStyle(PrimaryButtonStyle(height: 54))
                .disabled(req.cwd.isEmpty || busy)
                .padding(.horizontal, Spacing.page).padding(.bottom, 8)
            }
        }
    }

    /// 换 Agent 时把模式 / 模型 / 强度换成该 Agent 上次用的值。
    private func applyDefaults() {
        let d = store.settings.defaults(for: req.agent)
        req.mode = d.mode; req.model = d.model; req.effort = d.effort
    }

    private func start() async {
        busy = true
        var r = req
        r.firstMessage = firstMessage.isEmpty ? nil : firstMessage
        do { _ = try await store.createSession(r); dismiss() } catch { store.toast = error.localizedDescription }
        busy = false
    }
}
