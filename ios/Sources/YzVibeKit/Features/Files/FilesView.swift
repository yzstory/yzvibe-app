import SwiftUI
import UIKit

/// 远程文件：面包屑 + 列表 + 预览。只预览与下载，手机不执行任何文件。
struct FilesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    let session: Session?
    @State private var path = ""
    @State private var entries: [FileEntry] = []
    @State private var opened: FileRef?

    private var crumbs: [String] { path.split(separator: "/").map(String.init) }

    var body: some View {
        List {
            Section {
                ForEach(entries) { e in
                    Button { open(e) } label: { FileRow(entry: e) }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 4, leading: Spacing.card, bottom: 4, trailing: Spacing.card))
                        .swipeActions(edge: .trailing) {
                            Button { UIPasteboard.general.string = e.path; store.toast = "已复制路径" } label: {
                                Label("复制路径", systemImage: "doc.on.doc")
                            }
                            .tint(p.labelSecondary)
                        }
                        .contextMenu {
                            Button { UIPasteboard.general.string = e.path; store.toast = "已复制路径" } label: { Label("复制路径", systemImage: "doc.on.doc") }
                        }
                }
            } header: {
                breadcrumbs
            } footer: {
                Label("点文件可查看、复制内容或下载；手机不会执行任何文件", systemImage: "lock")
                    .font(.yzFootnote).foregroundStyle(p.labelTertiary)
                    .padding(.top, 6)
            }
        }
        .listStyle(.insetGrouped)
        .paperBackground()
        .navigationTitle("文件")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("刷新")
            }
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView("这个目录是空的", systemImage: "folder", description: Text("换个目录，或在电脑上确认路径。"))
            }
        }
        .navigationDestination(item: $opened) { ref in FileViewerView(session: session, path: ref.path) }
        .refreshable { await load() }
        .task { await load() }
    }

    /// 面包屑：跟随 Section header，点任意一段可以跳回上级。
    private var breadcrumbs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                Button { path = ""; Task { await load() } } label: { Chip("~", tone: crumbs.isEmpty ? .brand : .fill, mono: true) }
                    .buttonStyle(.plain)
                ForEach(Array(crumbs.enumerated()), id: \.offset) { i, c in
                    Image(systemName: "chevron.right").font(.system(.caption2, weight: .semibold)).foregroundStyle(p.labelTertiary)
                    Button {
                        path = crumbs.prefix(i + 1).joined(separator: "/")
                        Task { await load() }
                    } label: { Chip(c, tone: i == crumbs.count - 1 ? .brand : .fill, mono: true) }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .textCase(nil)
    }

    private func load() async {
        guard let session, let device = store.device(session.deviceId) else { entries = MockData.files; return }
        do { entries = try await store.client.listFiles(device: device, sessionId: session.id, path: path) } catch { store.toast = error.localizedDescription }
    }

    private func open(_ e: FileEntry) {
        if e.kind == .folder { path = e.path; Task { await load() }; return }
        opened = FileRef(path: e.path)
    }

    func symbol(for kind: FileEntry.Kind) -> String {
        switch kind { case .folder: "folder"; case .code: "doc.text"; case .markdown: "text.document"; case .image: "photo"; case .other: "doc" }
    }
}

struct FileRow: View {
    @Environment(\.palette) private var p
    let entry: FileEntry
    private var tint: Color {
        switch entry.kind { case .folder: p.amberSoft; case .code: p.blueSoft; case .markdown: p.sageSoft; case .image: p.purpleSoft; case .other: p.fill }
    }
    private var symbol: String {
        switch entry.kind { case .folder: "folder"; case .code: "doc.text"; case .markdown: "text.document"; case .image: "photo"; case .other: "doc" }
    }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(.subheadline, weight: .semibold)).foregroundStyle(p.labelSecondary)
                .frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint))
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).font(.system(.callout, weight: .semibold)).foregroundStyle(p.label).lineLimit(1)
                Text(meta).font(.yzCaption).foregroundStyle(p.labelTertiary)
            }
            Spacer(minLength: 4)
            if let b = entry.badge { Chip(b, tone: b == "审批中" ? .danger : .sage) }
            Image(systemName: "chevron.right").font(.system(.caption, weight: .semibold)).foregroundStyle(p.labelTertiary)
        }
        .frame(minHeight: 52)
    }
    private var meta: String {
        let size = entry.kind == .folder ? "" : ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file) + " · "
        return size + RelativeTime.string(from: entry.modifiedAt)
    }
}
