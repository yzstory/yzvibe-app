import SwiftUI

struct SessionsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @State private var query = ""
    @State private var activeOnly = false
    @State private var showNew = false
    @State private var collapsed: Set<String> = []

    var body: some View {
        NavigationStack {
            PageScaffold(eyebrow: store.selectedDevice?.name ?? "未选择设备", title: "会话") {
                DevicePickerChip()
            } content: {
                HStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(p.labelTertiary)
                        TextField("搜索会话或路径", text: $query).font(.yzCallout).fontWeight(.regular)
                    }
                    .padding(.horizontal, 16).frame(height: 46)
                    .background(Capsule().fill(p.fill).overlay(Capsule().strokeBorder(p.border, lineWidth: 1)))
                    Button { withAnimation(Motion.quick) { activeOnly.toggle() } } label: {
                        Text("仅活跃").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(activeOnly ? p.brand : p.labelSecondary)
                            .padding(.horizontal, 14).frame(height: 46)
                            .background(Capsule().fill(activeOnly ? p.brandSoft : p.fill).overlay(Capsule().strokeBorder(activeOnly ? p.brand.opacity(0.4) : p.border, lineWidth: 1)))
                    }
                    .buttonStyle(.plain)
                }

                let list = store.sessions(for: store.selectedDevice, activeOnly: activeOnly, query: query)
                if list.isEmpty {
                    PaperCard {
                        VStack(spacing: 10) {
                            Image(systemName: "bubble.left.and.text.bubble.right").font(.system(size: 36, weight: .light)).foregroundStyle(p.brand)
                            Text("这台电脑还没有会话").font(.yzHeadline).foregroundStyle(p.label)
                            Text("点右下角「新建会话」，选择 Agent 与工作目录。").font(.yzSubhead).foregroundStyle(p.labelSecondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity)
                    }
                } else if store.settings.groupByFolder {
                    ForEach(store.groupedSessions(list), id: \.cwd) { group in
                        FolderHeader(cwd: group.cwd, count: group.sessions.count, collapsed: collapsed.contains(group.cwd)) {
                            withAnimation(Motion.quick) { if collapsed.contains(group.cwd) { collapsed.remove(group.cwd) } else { collapsed.insert(group.cwd) } }
                        }
                        if !collapsed.contains(group.cwd) {
                            ForEach(group.sessions) { s in
                                NavigationLink(value: s.id) { SessionCard(session: s) }.buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    ForEach(list) { s in NavigationLink(value: s.id) { SessionCard(session: s) }.buttonStyle(.plain) }
                }
            }
            .navigationDestination(for: String.self) { ChatView(sessionId: $0) }
            .overlay(alignment: .bottomTrailing) {
                Button { showNew = true } label: { Label("新建会话", systemImage: "plus") }
                    .buttonStyle(PrimaryButtonStyle(height: 56))
                    .fixedSize()
                    .padding(.trailing, Spacing.page).padding(.bottom, 12)
            }
            .sheet(isPresented: $showNew) { NewSessionView().presentationDetents([.large]) }
            .refreshable { if let d = store.selectedDevice { await store.refresh(d) } }
        }
    }
}

/// 顶部「已连接 ▾」胶囊：切换设备。
struct DevicePickerChip: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    var body: some View {
        Menu {
            ForEach(store.devices) { d in
                Button { store.selectedDeviceId = d.id } label: {
                    Label(d.name, systemImage: d.online ? "circle.fill" : "circle")
                }
            }
        } label: {
            HStack(spacing: 6) {
                StatusDot(store.selectedDevice?.online == true ? .sage : .off)
                Text(store.selectedDevice?.online == true ? "已连接" : "离线").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.label)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(p.labelSecondary)
            }
            .padding(.horizontal, 12).frame(height: 36)
            .liquidGlass(in: Capsule(), interactive: true)
        }
    }
}

struct FolderHeader: View {
    @Environment(\.palette) private var p
    let cwd: String
    let count: Int
    let collapsed: Bool
    let toggle: () -> Void
    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(p.labelSecondary).frame(width: 14)
                Image(systemName: "folder").foregroundStyle(p.labelSecondary)
                Text((cwd as NSString).lastPathComponent).font(.system(size: 16, weight: .semibold)).foregroundStyle(p.label)
                Text(cwd).font(.yzMono).foregroundStyle(p.labelTertiary).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Text("\(count) 个").font(.yzFootnote).foregroundStyle(p.labelSecondary)
            }
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
    }
}

struct SessionCard: View {
    @Environment(\.palette) private var p
    let session: Session
    var body: some View {
        PaperCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    StatusDot(session: session.status)
                    Chip.agent(session.agent)
                    if session.pendingApprovals > 0 { Chip("\(session.pendingApprovals) 待审批", tone: .danger) }
                    Spacer(minLength: 4)
                    Text("\(session.status.displayName) · \(RelativeTime.string(from: session.updatedAt))").font(.yzFootnote).foregroundStyle(p.labelTertiary)
                }
                Text(session.title).font(.system(size: 18, weight: .semibold)).foregroundStyle(p.label).lineLimit(2)
                CodeBlock(session.cwd)
            }
        }
    }
}
