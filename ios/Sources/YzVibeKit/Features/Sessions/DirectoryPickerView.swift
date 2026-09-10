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
            List {
                Section {
                    if loading && listing == nil {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if let entries = listing?.entries, !entries.isEmpty {
                        ForEach(entries) { e in
                            Button { Task { await load(e.path) } } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "folder").foregroundStyle(p.brand)
                                    Text(e.name).font(.yzMonoBody).foregroundStyle(p.label).lineLimit(1)
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right").font(.system(.caption, weight: .semibold)).foregroundStyle(p.labelTertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Text("这个目录下没有子文件夹").font(.yzSubhead).foregroundStyle(p.labelTertiary)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(listing?.path ?? initialPath ?? "…")
                            .font(.yzMono).foregroundStyle(p.label).lineLimit(1).truncationMode(.head)
                        HStack(spacing: 6) {
                            if let parent = listing?.parent {
                                Button { Task { await load(parent) } } label: {
                                    Chip("上级 \((parent as NSString).lastPathComponent)", tone: .brand, icon: "arrow.up")
                                }.buttonStyle(.plain)
                            }
                            if let home = listing?.home, home != listing?.path {
                                Button { Task { await load(home) } } label: { Chip("主目录", tone: .fill, icon: "house") }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .textCase(nil)
                    .padding(.bottom, 4)
                } footer: {
                    if let error { Text(error).foregroundStyle(p.danger) }
                }
            }
            .listStyle(.insetGrouped)
            .paperBackground()
            .navigationTitle("选择目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNewFolder = true } label: { Image(systemName: "folder.badge.plus") }
                        .disabled(listing == nil)
                        .accessibilityLabel("新建文件夹")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { if let path = listing?.path { onPick(path); dismiss() } } label: {
                    Label("选择此文件夹", systemImage: "checkmark")
                }
                .buttonStyle(PrimaryButtonStyle(height: 52))
                .disabled(listing == nil)
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
