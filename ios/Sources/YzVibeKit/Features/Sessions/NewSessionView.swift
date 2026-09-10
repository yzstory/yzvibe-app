import SwiftUI

/// 新建会话：助手 / 工作目录（浏览、收藏）/ 首句消息（历史、模板）/ 会话模式（继续上次、Plan-Normal-Trust、模型、思考强度）/ 启动摘要。
struct NewSessionView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    /// 从聊天里的 /new 打开时，把当前会话的目录与 Agent 带过来
    var presetCwd: String? = nil
    var presetAgent: AgentKind? = nil
    var presetFirstMessage: String? = nil
    @State private var req = NewSessionRequest()
    @State private var firstMessage = ""
    @State private var busy = false
    @State private var seeded = false
    @State private var showPicker = false
    @State private var prefs = LocalPrefs.load()

    private var caps: AgentCapabilities { store.capabilities(for: req.agent, on: store.selectedDeviceId) }

    /// 收藏 → 最近用过 → 当前设备已有会话的目录，去重。
    private var suggestedDirs: [String] {
        var seen = Set<String>(); var out: [String] = []
        let fromSessions = store.sessions.filter { $0.deviceId == store.selectedDevice?.id }.sorted { $0.updatedAt > $1.updatedAt }.map(\.cwd)
        for d in prefs.favoriteDirs + prefs.recentDirs + fromSessions where !d.isEmpty && seen.insert(d).inserted { out.append(d) }
        return Array(out.prefix(8))
    }
    private var isFavorite: Bool { !req.cwd.isEmpty && prefs.favoriteDirs.contains(req.cwd) }

    var body: some View {
        NavigationStack {
            Form {
                Section("助手") {
                    Picker("助手", selection: $req.agent) {
                        ForEach(AgentKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }

                Section {
                    HStack(spacing: 10) {
                        TextField("~/project", text: $req.cwd)
                            .font(.yzMonoBody).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button { toggleFavorite() } label: {
                            Image(systemName: isFavorite ? "star.fill" : "star").foregroundStyle(isFavorite ? p.amber : p.labelTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isFavorite ? "取消收藏此目录" : "收藏此目录")
                        Button { showPicker = true } label: { Image(systemName: "folder") }
                            .buttonStyle(.plain).foregroundStyle(p.brand)
                            .accessibilityLabel("浏览目录")
                    }
                    if !suggestedDirs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(suggestedDirs, id: \.self) { f in
                                    Button { req.cwd = f } label: {
                                        Chip((f as NSString).lastPathComponent, tone: f == req.cwd ? .brand : .fill,
                                             icon: prefs.favoriteDirs.contains(f) ? "star.fill" : nil, mono: true)
                                    }.buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    Text("工作目录")
                }

                Section {
                    TextField("例如：整理这些笔记，摘要日志，或继续上次的远程会话", text: $firstMessage, axis: .vertical)
                        .lineLimit(3...6).font(.yzSubhead)
                } header: {
                    HStack {
                        Text("首句消息")
                        Spacer()
                        Menu {
                            ForEach(prefs.recentPrompts, id: \.self) { t in Button(String(t.prefix(40))) { firstMessage = t } }
                            Divider()
                            Button("清空历史", role: .destructive) { prefs.recentPrompts = []; prefs.save() }
                        } label: { Image(systemName: "clock") }
                        .disabled(prefs.recentPrompts.isEmpty)
                        .accessibilityLabel("最近用过的首句")
                        Menu {
                            ForEach(LocalPrefs.templates, id: \.title) { t in Button(t.title) { firstMessage = t.body } }
                        } label: { Image(systemName: "plus") }
                        .accessibilityLabel("从模板插入")
                    }
                    .textCase(nil)
                } footer: {
                    Text("可选。填写后，会在会话创建成功后自动发送。")
                }

                Section("会话模式") { modeRows }

                Section("启动摘要") { summaryRow }
            }
            .paperBackground()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("新建会话")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if !seeded {
                    seeded = true
                    if let a = presetAgent { req.agent = a }
                    applyDefaults()
                    if let a = presetAgent { req.agent = a }
                    if let c = presetCwd, !c.isEmpty { req.cwd = c }
                    if let m = presetFirstMessage, !m.isEmpty { firstMessage = m }
                }
                if req.cwd.isEmpty { req.cwd = presetCwd ?? suggestedDirs.first ?? "" }
            }
            .onChange(of: req.agent) { _, _ in applyDefaults() }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button { Task { await start() } } label: {
                    if busy { ProgressView().tint(p.brandInk) } else { Label("开始会话", systemImage: "arrow.right") }
                }
                .buttonStyle(PrimaryButtonStyle(height: 52))
                .disabled(req.cwd.isEmpty || busy)
                .padding(.horizontal, Spacing.page).padding(.bottom, 8)
            }
            .sheet(isPresented: $showPicker) {
                DirectoryPickerView(initialPath: req.cwd.isEmpty ? nil : req.cwd) { req.cwd = $0 }
            }
        }
    }

    // MARK: 会话模式：继续上次 / 模式 / 模型 / 思考强度

    private var modeRows: some View {
        Group {
            Toggle(isOn: $req.continueLast) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("继续上次").font(.yzBody).foregroundStyle(p.label)
                    Text("进入该目录最近一次会话").font(.yzFootnote).foregroundStyle(p.labelSecondary)
                }
            }
            modeRow("模式", caps.modeInfo(req.mode)?.description ?? req.mode.subtitle, danger: req.mode == .trust) {
                ModeMenu(agent: req.agent, caps: caps, mode: $req.mode)
            }
            modeRow("模型", caps.label(forModel: req.model)) {
                ModelMenu(agent: req.agent, caps: caps, model: $req.model)
            }
            modeRow("思考强度", EffortLevel.displayName(req.effort)) {
                EffortMenu(agent: req.agent, caps: caps, model: req.model, effort: $req.effort)
            }
        }
    }

    private func modeRow<T: View>(_ title: String, _ subtitle: String, danger: Bool = false, @ViewBuilder trailing: @escaping () -> T) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.yzBody).foregroundStyle(p.label)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.yzFootnote).foregroundStyle(danger ? p.danger : p.labelSecondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
    }

    // MARK: 启动摘要

    private var summaryRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(req.agent.displayName) · \(caps.label(forModel: req.model))").font(.yzTitle3).foregroundStyle(p.label)
            Text(req.cwd.isEmpty ? "未选择工作目录" : req.cwd)
                .font(.yzMono).foregroundStyle(p.labelSecondary).lineLimit(2).truncationMode(.middle)
            HStack(spacing: 6) {
                Chip(req.mode.displayName, tone: req.mode == .trust ? .danger : req.mode == .plan ? .warning : .brand, icon: req.mode.symbol)
                if req.effort != nil { Chip("思考 \(EffortLevel.displayName(req.effort))", tone: .fill) }
                if req.continueLast { Chip("继续上次", tone: .sage) }
            }
            if let flag = caps.modeInfo(req.mode)?.flag {
                Text(flag).font(.yzCaption).monospaced().foregroundStyle(p.labelTertiary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: helpers

    private func toggleFavorite() {
        guard !req.cwd.isEmpty else { return }
        if isFavorite { prefs.favoriteDirs.removeAll { $0 == req.cwd } } else { prefs.favoriteDirs.insert(req.cwd, at: 0) }
        prefs.save()
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
        if !firstMessage.isEmpty {
            prefs.recentPrompts.removeAll { $0 == firstMessage }
            prefs.recentPrompts.insert(firstMessage, at: 0)
            prefs.recentPrompts = Array(prefs.recentPrompts.prefix(10))
        }
        prefs.recentDirs.removeAll { $0 == r.cwd }
        prefs.recentDirs.insert(r.cwd, at: 0)
        prefs.recentDirs = Array(prefs.recentDirs.prefix(10))
        prefs.save()
        do { _ = try await store.createSession(r); dismiss() } catch { store.toast = error.localizedDescription }
        busy = false
    }
}
