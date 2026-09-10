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
            List {
                if let note = catalog?.note {
                    Section {
                        Label(note, systemImage: "info.circle")
                            .font(.yzFootnote).foregroundStyle(p.labelSecondary)
                    }
                }
                section("手机端", filter(catalog?.app ?? []), tone: .brand)
                section("\(agent.displayName) 命令", filter(catalog?.agentCommands ?? []), tone: .fill)
                section("Skill", filter(catalog?.skills ?? []), tone: .fill)
                section("自定义提示词", filter(catalog?.prompts ?? []), tone: .claude)
            }
            .listStyle(.insetGrouped)
            .paperBackground()
            .navigationTitle("命令与 Skill")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索命令或 skill")
            .overlay {
                if loading && catalog == nil {
                    ProgressView()
                } else if isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
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
            Section {
                ForEach(items) { cmd in
                    Button { onPick(cmd); dismiss() } label: { CommandRow(cmd: cmd, tone: tone) }
                        .buttonStyle(.plain)
                }
            } header: {
                HStack {
                    Text(title)
                    Spacer()
                    Text("\(items.count)")
                }
            }
        }
    }
}

/// 一条命令：名字 + 说明 + 来源标记。
struct CommandRow: View {
    @Environment(\.palette) private var p
    let cmd: SlashCommand
    let tone: ChipTone
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cmd.isApp || !cmd.insertAsText ? "/\(cmd.name)" : cmd.name)
                    .font(.yzMonoBody).foregroundStyle(p.label).lineLimit(1)
                if !cmd.description.isEmpty {
                    Text(cmd.description).font(.yzFootnote).foregroundStyle(p.labelSecondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if cmd.isApp { Chip("手机", tone: tone) }
            Image(systemName: "chevron.right").font(.system(.caption, weight: .semibold)).foregroundStyle(p.labelTertiary)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
