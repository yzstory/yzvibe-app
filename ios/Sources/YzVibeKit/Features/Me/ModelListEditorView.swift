import SwiftUI

/// 「模型列表」：按 Agent 维护会话里可选的模型（id + 显示名）。改过后覆盖连接器 / 内置列表；可一键恢复默认。
struct ModelListEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @State private var agent: AgentKind = .claude
    @State private var editing: ModelOption?
    @State private var adding = false

    private var caps: AgentCapabilities { store.capabilities(for: agent, on: store.selectedDeviceId) }
    private var customized: Bool { store.settings.modelPresets(for: agent) != nil }
    private var list: [ModelOption] { store.modelOptions(for: agent, caps: caps) }

    var body: some View {
        List {
            Section {
                Picker("助手", selection: $agent) {
                    Text("Claude").tag(AgentKind.claude)
                    Text("Codex").tag(AgentKind.codex)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            } footer: {
                Text(agent == .claude
                     ? "ID 原样传给 claude 的 --model。写完整 ID（如 claude-opus-5）可锁定版本；写别名（opus / sonnet / fable）则随 CLI 指向最新。"
                     : "ID 原样传给 codex 的 -m。默认列表来自电脑上 codex debug models 的目录。")
            }

            Section(customized ? "自定义列表" : "默认列表") {
                ForEach(list) { m in
                    Button { editing = m } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "cpu").font(.system(.subheadline, weight: .semibold))
                                .foregroundStyle(p.purple).frame(width: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(m.label).font(.yzBody).foregroundStyle(p.label)
                                Text(m.id).font(.yzMono).foregroundStyle(p.labelSecondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "pencil").font(.system(.footnote, weight: .semibold)).foregroundStyle(p.labelTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    // 之前这些手势挂在普通 Button 上，不在 List 里所以从来没生效过
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { remove(m) } label: { Label("删除", systemImage: "trash") }
                    }
                    .contextMenu { Button(role: .destructive) { remove(m) } label: { Label("删除", systemImage: "trash") } }
                }
            }

            Section {
                Button { adding = true } label: { Label("添加模型", systemImage: "plus") }
                if customized {
                    Button { store.settings.setModelPresets(nil, for: agent) } label: {
                        Label("恢复默认", systemImage: "arrow.counterclockwise")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .paperBackground()
        .navigationTitle("模型列表")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { m in ModelEditSheet(agent: agent, original: m) { save($0, replacing: m) } }
        .sheet(isPresented: $adding) { ModelEditSheet(agent: agent, original: nil) { save($0, replacing: nil) } }
    }

    private func save(_ m: ModelOption, replacing old: ModelOption?) {
        var l = list
        if let old, let i = l.firstIndex(where: { $0.id == old.id }) { l[i] = m } else { l.removeAll { $0.id == m.id }; l.append(m) }
        store.settings.setModelPresets(l, for: agent)
    }
    private func remove(_ m: ModelOption) {
        var l = list; l.removeAll { $0.id == m.id }
        store.settings.setModelPresets(l, for: agent)
    }
}

struct ModelEditSheet: View {
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    let agent: AgentKind
    let original: ModelOption?
    let onSave: (ModelOption) -> Void
    @State private var id = ""
    @State private var label = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("模型 ID") {
                    TextField(agent == .claude ? "claude-opus-5" : "gpt-5.5", text: $id)
                        .font(.yzMonoBody).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("显示名（可选）") {
                    TextField(agent == .claude ? "Opus 5" : "GPT-5.5", text: $label)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
            .paperBackground()
            .navigationTitle(original == nil ? "添加模型" : "编辑模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let i = id.trimmingCharacters(in: .whitespacesAndNewlines), l = label.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(ModelOption(id: i, label: l.isEmpty ? i : l, description: original?.description, efforts: original?.efforts, defaultEffort: original?.defaultEffort))
                        dismiss()
                    }
                    .disabled(id.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { id = original?.id ?? ""; label = original?.label ?? "" }
        }
        .presentationDetents([.medium])
    }

}
