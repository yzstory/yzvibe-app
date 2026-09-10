import SwiftUI

/// 命令面板：手机端自己的命令、Agent 的斜杠命令、以及电脑上装了哪些 skill。
/// 清单来自连接器——Claude 会在会话启动时自报它这一次真正能用的命令，比写死一份准。
struct CommandPaletteView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    let sessionId: String
    /// 选中一条：app 命令交给 ChatView 执行，其余的插进输入框。
    let onPick: (SlashCommand) -> Void

    @State private var catalog: CommandCatalog?
    @State private var query = ""
    @State private var loading = true

    private var agent: AgentKind { store.session(sessionId)?.agent ?? .claude }

    private func filter(_ list: [SlashCommand]) -> [SlashCommand] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "/", with: "")
        guard !q.isEmpty else { return list }
        return list.filter { $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let note = catalog?.note {
                            HStack(spacing: 10) {
                                Image(systemName: "info.circle").foregroundStyle(p.blue)
                                Text(note).font(.yzFootnote).foregroundStyle(p.labelSecondary)
                            }
                            .padding(14)
                            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        section("手机端", filter(catalog?.app ?? []), tone: .brand)
                        section("\(agent.displayName) 命令", filter(catalog?.agentCommands ?? []), tone: .custom)
                        section("Skill", filter(catalog?.skills ?? []), tone: .codex)
                        section("自定义提示词", filter(catalog?.prompts ?? []), tone: .claude)
                        if loading && catalog == nil { ProgressView().frame(maxWidth: .infinity).padding(.top, 40) }
                        else if isEmpty { Text("没有匹配的命令").font(.yzSubhead).foregroundStyle(p.labelTertiary).frame(maxWidth: .infinity).padding(.top, 40) }
                    }
                    .padding(Spacing.page)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("命令与 Skill")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索命令或 skill")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .task { catalog = await store.commands(for: sessionId); loading = false }
        }
    }

    private var isEmpty: Bool {
        guard let c = catalog else { return false }
        return filter(c.app).isEmpty && filter(c.agentCommands).isEmpty && filter(c.skills).isEmpty && filter(c.prompts).isEmpty
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [SlashCommand], tone: ChipTone) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow(title)
                    Spacer()
                    Text("\(items.count)").font(.yzCaption).foregroundStyle(p.labelTertiary)
                }
                PaperCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, cmd in
                            Button { onPick(cmd); dismiss() } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(cmd.display).font(.yzMonoBody).foregroundStyle(p.label).lineLimit(1)
                                        if !cmd.description.isEmpty {
                                            Text(cmd.description).font(.yzFootnote).foregroundStyle(p.labelSecondary).lineLimit(2).multilineTextAlignment(.leading)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    if !cmd.source.isEmpty { Chip(cmd.source, tone: tone) }
                                }
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if i < items.count - 1 { Divider_() }
                        }
                    }
                }
            }
        }
    }
}
