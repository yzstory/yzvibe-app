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
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SegmentedPills(items: [(AgentKind.claude, "Claude"), (.codex, "Codex")], selection: $agent)
                    Text(agent == .claude
                         ? "ID 原样传给 claude 的 --model。写完整 ID（如 claude-opus-5）可锁定版本；写别名（opus / sonnet / fable）则随 CLI 指向最新。"
                         : "ID 原样传给 codex 的 -m。默认列表来自电脑上 codex debug models 的目录。")
                        .font(.yzFootnote).foregroundStyle(p.labelSecondary)
                    SectionCard(customized ? "自定义列表" : "默认列表") {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, m in
                            if i > 0 { Divider_() }
                            Button { editing = m } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "cpu").font(.system(size: 15, weight: .semibold)).foregroundStyle(p.purple).frame(width: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(m.label).font(.yzBody).foregroundStyle(p.label)
                                        Text(m.id).font(.yzMono).foregroundStyle(p.labelSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "pencil").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.labelTertiary)
                                }
                                .padding(.horizontal, Spacing.card).frame(minHeight: 56)
                            }
                            .buttonStyle(.plain)
                            .swipeActions { Button(role: .destructive) { remove(m) } label: { Label("删除", systemImage: "trash") } }
                            .contextMenu { Button(role: .destructive) { remove(m) } label: { Label("删除", systemImage: "trash") } }
                        }
                    }
                    HStack(spacing: 10) {
                        Button { adding = true } label: { Label("添加模型", systemImage: "plus") }.buttonStyle(.yzSecondary)
                        if customized { Button { store.settings.setModelPresets(nil, for: agent) } label: { Label("恢复默认", systemImage: "arrow.counterclockwise") }.buttonStyle(.yzGlass) }
                    }
                }
                .padding(Spacing.page).padding(.bottom, 60)
            }
        }
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
            ZStack {
                AmbientBackground()
                VStack(alignment: .leading, spacing: 16) {
                    field("模型 ID", text: $id, placeholder: agent == .claude ? "claude-opus-5" : "gpt-5.5", mono: true)
                    field("显示名（可选）", text: $label, placeholder: agent == .claude ? "Opus 5" : "GPT-5.5", mono: false)
                    Spacer()
                }
                .padding(Spacing.page)
            }
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

    private func field(_ title: String, text: Binding<String>, placeholder: String, mono: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(title)
            TextField(placeholder, text: text)
                .font(mono ? .yzMonoBody : .yzBody)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(.horizontal, 16).frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(p.fill).overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(p.border, lineWidth: 1)))
        }
    }
}
