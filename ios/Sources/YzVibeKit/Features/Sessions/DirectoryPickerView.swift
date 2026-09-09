import SwiftUI

// MARK: - 本地偏好：收藏目录 / 最近目录 / 最近首句 / 模板（只存手机）

struct LocalPrefs: Codable {
    var favoriteDirs: [String] = []
    var recentDirs: [String] = []
    var recentPrompts: [String] = []

    static let templates: [(title: String, body: String)] = [
        ("继续上次的工作", "继续上次的工作，先总结一下当前进度，再告诉我下一步。"),
        ("代码审查", "审查最近一次提交的改动，指出正确性问题和可简化的地方。"),
        ("修复测试", "运行测试，修复所有失败的用例，每一步先告诉我原因。"),
        ("整理笔记", "整理这个目录里的笔记，按主题归类并生成摘要。"),
    ]

    static func load() -> LocalPrefs {
        guard let d = UserDefaults.standard.data(forKey: "yz.localPrefs"), let p = try? JSONDecoder().decode(LocalPrefs.self, from: d) else { return LocalPrefs() }
        return p
    }
    func save() { if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: "yz.localPrefs") } }
}

// MARK: - 目录选择器：浏览电脑文件系统 → 选择此文件夹

struct DirectoryPickerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    let initialPath: String?
    let onPick: (String) -> Void
    @State private var listing: DirectoryListing?
    @State private var error: String?
    @State private var newFolderName = ""
    @State private var showNewFolder = false
    @State private var loading = false

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "folder").font(.system(size: 22)).foregroundStyle(p.brand)
                            .frame(width: 52, height: 52).background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(p.brandSoft))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("选择目录").font(.yzTitle2).foregroundStyle(p.label)
                            Text("在电脑文件系统中浏览并选择一个文件夹。").font(.yzFootnote).foregroundStyle(p.labelSecondary)
                        }
                        Spacer()
                        Button { showNewFolder = true } label: {
                            Image(systemName: "folder.badge.plus").font(.system(size: 16, weight: .semibold)).foregroundStyle(p.label)
                                .frame(width: 44, height: 44).background(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(p.border, lineWidth: 1))
                        }
                        .disabled(listing == nil)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.turn.down.right").font(.system(size: 12)).foregroundStyle(p.labelTertiary)
                        Text(listing?.path ?? initialPath ?? "…").font(.yzMono).foregroundStyle(p.label).lineLimit(1).truncationMode(.head)
                    }
                    .padding(.horizontal, 14).frame(height: 46).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(p.fill).overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(p.border, lineWidth: 1)))
                    HStack(spacing: 8) {
                        if let parent = listing?.parent {
                            Button { Task { await load(parent) } } label: { Chip("上级目录 \((parent as NSString).lastPathComponent)", tone: .brand, icon: "arrow.up") }.buttonStyle(.plain)
                        }
                        if let home = listing?.home, home != listing?.path {
                            Button { Task { await load(home) } } label: { Chip("主目录", tone: .fill, icon: "house") }.buttonStyle(.plain)
                        }
                    }
                    if let error { Text(error).font(.yzFootnote).foregroundStyle(p.danger) }
                    PaperCard(padding: 0) {
                        if loading && listing == nil {
                            ProgressView().frame(maxWidth: .infinity).padding(30)
                        } else if let entries = listing?.entries, !entries.isEmpty {
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                                        Button { Task { await load(e.path) } } label: {
                                            HStack(spacing: 12) {
                                                Image(systemName: "folder").foregroundStyle(p.brand)
                                                Text(e.name).font(.yzMonoBody).foregroundStyle(p.label).lineLimit(1)
                                                Spacer()
                                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(p.labelTertiary)
                                            }
                                            .padding(.horizontal, Spacing.card).frame(minHeight: 52)
                                        }.buttonStyle(.plain)
                                        if i < entries.count - 1 { Divider_() }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        } else {
                            Text("这个目录下没有子文件夹").font(.yzSubhead).foregroundStyle(p.labelTertiary).frame(maxWidth: .infinity).padding(30)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(Spacing.page)
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Button("取消") { dismiss() }.buttonStyle(OutlineButtonStyle(height: 52)).frame(maxWidth: 150)
                    Button { if let path = listing?.path { onPick(path); dismiss() } } label: { Label("选择此文件夹", systemImage: "checkmark") }
                        .buttonStyle(PrimaryButtonStyle(height: 52)).disabled(listing == nil)
                }
                .padding(.horizontal, Spacing.page).padding(.bottom, 8)
            }
            .alert("新建文件夹", isPresented: $showNewFolder) {
                TextField("名称", text: $newFolderName)
                Button("创建") { Task { await createFolder() } }
                Button("取消", role: .cancel) {}
            } message: { Text("将在当前目录下创建") }
            .task { await load(initialPath) }
        }
    }

    private func load(_ path: String?) async {
        guard let d = store.selectedDevice else { error = "未选择设备"; return }
        loading = true; error = nil
        do { listing = try await store.client.listDirectories(device: d, path: path) }
        catch let e {
            error = e.localizedDescription
            if path != nil, listing == nil { listing = try? await store.client.listDirectories(device: d, path: nil) }
        }
        loading = false
    }

    private func createFolder() async {
        guard let d = store.selectedDevice, let parent = listing?.path, !newFolderName.isEmpty else { return }
        do { let path = try await store.client.makeDirectory(device: d, parent: parent, name: newFolderName); newFolderName = ""; await load(path) }
        catch let e { error = e.localizedDescription }
    }
}
