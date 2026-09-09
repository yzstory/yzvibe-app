import SwiftUI

struct NewSessionView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State private var req = NewSessionRequest(cwd: MockData.recentFolders.first ?? "")
    @State private var firstMessage = ""
    @State private var busy = false

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
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) { Text("YOLO 模式").font(.yzHeadline).foregroundStyle(p.label); Image(systemName: "bolt.fill").font(.system(size: 12)).foregroundStyle(p.danger) }
                                    Text("跳过所有权限检查，手机端不会再收到审批").font(.yzFootnote).foregroundStyle(p.labelSecondary)
                                    Text("--dangerously-skip-permissions").font(.yzCaption).monospaced().foregroundStyle(p.labelTertiary)
                                }
                                Spacer()
                                Toggle("", isOn: $req.yolo).labelsHidden().tint(p.danger)
                            }
                            .padding(.horizontal, Spacing.card).frame(minHeight: 76)
                        }
                    }
                    .padding(Spacing.page)
                    .padding(.bottom, 80)
                }
            }
            .navigationTitle("新建会话")
            .navigationBarTitleDisplayMode(.inline)
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

    private func start() async {
        busy = true
        var r = req
        r.firstMessage = firstMessage.isEmpty ? nil : firstMessage
        do { _ = try await store.createSession(r); dismiss() } catch { store.toast = error.localizedDescription }
        busy = false
    }
}
