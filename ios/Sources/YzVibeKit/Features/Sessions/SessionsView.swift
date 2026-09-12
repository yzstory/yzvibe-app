import SwiftUI
import UIKit

struct SessionsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var showNew = false
    @State private var collapsed: Set<String> = []
    @State private var path: [String] = []
    @State private var pendingDelete: Session?
    @State private var renaming: Session?

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--design-preview"),
           ProcessInfo.processInfo.arguments.contains("--design-chat") {
            _path = State(initialValue: ["s1"])
        }
        #endif
    }

    private var list: [Session] {
        store.sessions(for: store.selectedDevice, activeOnly: store.settings.activeOnly, query: query)
    }

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $path) {
            Group {
                if list.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .paperBackground()
            .navigationTitle("会话")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索会话或路径")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { DevicePickerMenu() }
                ToolbarItem(placement: .topBarTrailing) { filterMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    if store.settings.groupByFolder, !list.isEmpty {
                        let folders = Set(list.map(\.cwd))
                        let allCollapsed = folders.isSubset(of: collapsed)
                        Button {
                            withAnimation(reduceMotion ? nil : Motion.quick) {
                                if allCollapsed { collapsed.subtract(folders) }
                                else { collapsed.formUnion(folders) }
                            }
                        } label: {
                            Image(systemName: allCollapsed ? "chevron.down" : "chevron.up")
                        }
                        .accessibilityLabel(allCollapsed ? "展开全部分组" : "收拢全部分组")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("新建会话")
                }
            }
            .navigationDestination(for: String.self) { ChatView(sessionId: $0) }
            // 点开「回复完成」的推送时直接进到那个会话
            .onChange(of: store.openSessionRequest) { _, sid in
                guard let sid else { return }
                store.openSessionRequest = nil
                if path.last != sid { path = [sid] }
            }
            .sheet(item: $renaming) { RenameSessionView(session: $0) }
            .sheet(isPresented: $showNew) { NewSessionView().presentationDetents([.large]) }
            .refreshable { if let d = store.selectedDevice { await store.refresh(d) } }
            .confirmationDialog("删除会话", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), presenting: pendingDelete) { s in
                Button("删除「\(s.title)」", role: .destructive) {
                    let id = s.id
                    pendingDelete = nil
                    Task { await store.deleteSession(id) }
                }
            } message: { _ in
                Text("删除后会停止此会话，并清除 YzVibe 中的消息。电脑上 Claude / Codex 的原始记录会保留，可在「我 › 会话」中重新显示；尚未保存到电脑记录的内容无法恢复。")
            }
        }
    }

    // MARK: 列表

    @ViewBuilder
    private var sessionList: some View {
        List {
            if store.settings.groupByFolder {
                ForEach(store.groupedSessions(list), id: \.cwd) { group in
                    Section {
                        if !collapsed.contains(group.cwd) {
                            ForEach(group.sessions) { row($0) }
                        }
                    } header: {
                        FolderHeader(cwd: group.cwd, count: group.sessions.count, collapsed: collapsed.contains(group.cwd)) {
                            withAnimation(reduceMotion ? nil : Motion.quick) {
                                if collapsed.contains(group.cwd) { collapsed.remove(group.cwd) } else { collapsed.insert(group.cwd) }
                            }
                        }
                    }
                }
            } else {
                ForEach(list) { row($0) }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
        .environment(\.defaultMinListRowHeight, 0)
    }

    /// 一行 = 一张纸卡；分隔线交给卡片之间的留白，不用系统 separator。
    private func row(_ s: Session) -> some View {
        NavigationLink(value: s.id) { SessionCard(session: s) }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 5, leading: Spacing.page, bottom: 5, trailing: Spacing.page))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button { renaming = s } label: { Label("重命名", systemImage: "pencil") }
                    .buttonStyle(.automatic).tint(p.brand)
                // 确认前不使用 destructive role，避免系统先把行移走。
                Button { pendingDelete = s } label: { Label("删除", systemImage: "trash") }
                    .buttonStyle(.automatic)
                    .tint(p.danger)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                if s.status == .running {
                    Button { Task { await store.stop(s.id) } } label: { Label("停止", systemImage: "stop.fill") }
                        .buttonStyle(.automatic)
                        .tint(p.danger)
                }
                Button {
                    UIPasteboard.general.string = s.cwd
                    store.toast = "已复制工作目录"
                } label: { Label("复制路径", systemImage: "doc.on.doc") }
                .buttonStyle(.automatic)
                .tint(p.labelSecondary)
            }
            .contextMenu {
                Button { renaming = s } label: { Label("重命名", systemImage: "pencil") }
                Button { UIPasteboard.general.string = s.cwd } label: { Label("复制工作目录", systemImage: "doc.on.doc") }
                if s.status == .running {
                    Button(role: .destructive) { Task { await store.stop(s.id) } } label: { Label("停止", systemImage: "stop.fill") }
                }
                Button(role: .destructive) { pendingDelete = s } label: { Label("删除会话", systemImage: "trash") }
            }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(query.isEmpty ? (store.settings.activeOnly ? "暂无活跃会话" : "这台电脑还没有会话") : "没有匹配的会话", systemImage: "bubble.left.and.text.bubble.right")
        } description: {
            Text(store.settings.activeOnly ? "这里仅显示运行中、待审批或有排队任务的会话。关闭筛选可查看全部会话。" : (query.isEmpty ? "点右上角新建，选择 Agent 与工作目录。" : "换个关键词试试。"))
        } actions: {
            if store.settings.activeOnly {
                Button("查看全部会话") { store.settings.activeOnly = false }
            } else if query.isEmpty {
                Button("新建会话") { showNew = true }.buttonStyle(.borderedProminent).tint(p.brand)
            }
        }
    }

    private var filterMenu: some View {
        @Bindable var store = store
        return Menu {
            Toggle("仅显示活跃", isOn: $store.settings.activeOnly)
            Toggle("按文件夹分组", isOn: $store.settings.groupByFolder)
        } label: {
            Image(systemName: store.settings.activeOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("筛选")
    }
}

/// 导航栏左上的设备切换菜单。
struct DevicePickerMenu: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    var body: some View {
        Menu {
            Picker("设备", selection: Binding(get: { store.selectedDeviceId ?? "" }, set: { store.selectedDeviceId = $0 })) {
                ForEach(store.devices) { d in
                    Label(d.name, systemImage: d.online ? "desktopcomputer" : "desktopcomputer.trianglebadge.exclamationmark").tag(d.id)
                }
            }
        } label: {
            HStack(spacing: 5) {
                StatusDot(store.selectedDevice?.online == true ? .sage : .off)
                Text(store.selectedDevice?.name ?? "未选择设备")
                    .font(.yzFootnoteStrong)
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(.caption2, weight: .bold))
            }
            .foregroundStyle(p.labelSecondary)
        }
        .accessibilityLabel("切换设备，当前 \(store.selectedDevice?.name ?? "未选择")")
    }
}

/// 文件夹分组头：跟随系统 Section header 的观感（小写字重、贴左）。
struct FolderHeader: View {
    @Environment(\.palette) private var p
    let cwd: String
    let count: Int
    let collapsed: Bool
    let toggle: () -> Void
    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(.caption2, weight: .bold))
                    .frame(width: 12)
                Text((cwd as NSString).lastPathComponent).font(.yzFootnoteStrong).foregroundStyle(p.label)
                Text(cwd).font(.yzMono).foregroundStyle(p.labelTertiary).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Text("\(count)").font(.yzFootnote).foregroundStyle(p.labelTertiary)
            }
            .foregroundStyle(p.labelSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .listRowInsets(EdgeInsets(top: 10, leading: Spacing.page + 2, bottom: 4, trailing: Spacing.page))
    }
}

struct SessionCard: View {
    @Environment(\.palette) private var p
    let session: Session
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    if session.status == .running {
                        RunningSessionIndicator()
                    } else {
                        StatusDot(session: session.status)
                    }
                    Text(session.agent.displayName).font(.yzCaption).foregroundStyle(p.labelSecondary)
                    if session.source != .phone {
                        Chip(session.source.displayName, tone: .fill, icon: session.source == .terminal ? "terminal" : "shippingbox")
                    }
                    if session.pendingApprovals > 0 { Chip("\(session.pendingApprovals) 待审批", tone: .danger) }
                    Spacer(minLength: 4)
                    Text(RelativeTime.string(from: session.updatedAt))
                        .font(.yzFootnote).foregroundStyle(p.labelTertiary).lineLimit(1)
                }
                Text(session.title).font(.system(.body, weight: .semibold)).foregroundStyle(p.label).lineLimit(2)
                    .lineSpacing(3)
                HStack(spacing: 8) {
                    if let b = session.branch {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.branch").font(.system(.caption2, weight: .semibold))
                            Text(b).font(.yzMono)
                        }
                        .foregroundStyle(p.labelSecondary).lineLimit(1)
                    }
                    Image(systemName: "folder").font(.yzCaption).foregroundStyle(p.labelTertiary)
                    Text(session.cwd).font(.yzCaption).foregroundStyle(p.labelSecondary).lineLimit(1).truncationMode(.middle)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue(session.status.displayName)
    }
}

/// 仅运行中的卡片显示进度环；减少动态效果时使用静态标记。
private struct RunningSessionIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var p
    var body: some View {
        Group {
            if reduceMotion {
                Image(systemName: "ellipsis.circle").foregroundStyle(p.brand)
            } else {
                ProgressView().controlSize(.mini).tint(p.brand)
            }
        }
        .frame(width: 14, height: 14)
        .accessibilityLabel("正在运行")
    }
}

private struct RenameSessionView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let session: Session
    @State private var title: String
    @State private var saving = false
    @State private var failed = false
    @FocusState private var focused: Bool
    init(session: Session) {
        self.session = session
        _title = State(initialValue: session.title)
    }
    private var valid: Bool {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && value.utf16.count <= 200
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("显示名称") {
                    TextField("会话名称", text: $title, axis: .vertical)
                        .lineLimit(1...4).focused($focused).disabled(saving)
                }
                if failed {
                    Text("保存失败，请检查连接或更新电脑端连接器后重试。输入的名称已保留。")
                        .foregroundStyle(.red)
                }
                if !valid { Text("请输入 1–200 个字符的名称").foregroundStyle(.secondary) }
            }
            .paperBackground().navigationTitle("重命名会话").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "保存中…" : "保存") {
                        saving = true; failed = false
                        Task {
                            if await store.renameSession(session.id, to: title) { dismiss() }
                            else { failed = true }
                            saving = false
                        }
                    }.disabled(!valid || saving)
                }
            }
            .task { focused = true }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(saving)
    }
}
