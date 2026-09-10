import SwiftUI
import UIKit

struct SessionsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @State private var query = ""
    @State private var showNew = false
    @State private var collapsed: Set<String> = []
    @State private var path: [String] = []

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
            .sheet(isPresented: $showNew) { NewSessionView().presentationDetents([.large]) }
            .refreshable { if let d = store.selectedDevice { await store.refresh(d) } }
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
                            withAnimation(Motion.quick) {
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
        .environment(\.defaultMinListRowHeight, 0)
    }

    /// 一行 = 一张纸卡；分隔线交给卡片之间的留白，不用系统 separator。
    private func row(_ s: Session) -> some View {
        NavigationLink(value: s.id) { SessionCard(session: s) }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 5, leading: Spacing.page, bottom: 5, trailing: Spacing.page))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .swipeActions(edge: .trailing) {
                if s.status == .running {
                    Button { Task { await store.stop(s.id) } } label: { Label("停止", systemImage: "stop.fill") }
                        .tint(p.danger)
                }
                Button {
                    UIPasteboard.general.string = s.cwd
                    store.toast = "已复制工作目录"
                } label: { Label("复制路径", systemImage: "doc.on.doc") }
                .tint(p.labelSecondary)
            }
            .contextMenu {
                Button { UIPasteboard.general.string = s.cwd } label: { Label("复制工作目录", systemImage: "doc.on.doc") }
                if s.status == .running {
                    Button(role: .destructive) { Task { await store.stop(s.id) } } label: { Label("停止", systemImage: "stop.fill") }
                }
            }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(query.isEmpty ? "这台电脑还没有会话" : "没有匹配的会话", systemImage: "bubble.left.and.text.bubble.right")
        } description: {
            Text(query.isEmpty ? "点右上角新建，选择 Agent 与工作目录。" : "换个关键词，或清掉「仅活跃」筛选。")
        } actions: {
            if query.isEmpty {
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
        PaperCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    StatusDot(session: session.status)
                    Chip.agent(session.agent)
                    if session.source != .phone {
                        Chip(session.source.displayName, tone: .fill, icon: session.source == .terminal ? "terminal" : "shippingbox")
                    }
                    if session.pendingApprovals > 0 { Chip("\(session.pendingApprovals) 待审批", tone: .danger) }
                    Spacer(minLength: 4)
                    Text("\(session.status.displayName) · \(RelativeTime.string(from: session.updatedAt))")
                        .font(.yzFootnote).foregroundStyle(p.labelTertiary).lineLimit(1)
                }
                Text(session.title).font(.yzTitle3).foregroundStyle(p.label).lineLimit(2)
                HStack(spacing: 8) {
                    if let b = session.branch {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.branch").font(.system(.caption2, weight: .semibold))
                            Text(b).font(.yzMono)
                        }
                        .foregroundStyle(p.labelSecondary).lineLimit(1)
                    }
                    CodeBlock(session.cwd)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
