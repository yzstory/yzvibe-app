import SwiftUI

/// 远程文件：面包屑 + 列表 + 预览。只预览与下载，手机不执行任何文件。
struct FilesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    let session: Session?
    @State private var path = ""
    @State private var entries: [FileEntry] = []
    @State private var selected: FileEntry?
    @State private var preview = ""

    private var crumbs: [String] { path.split(separator: "/").map(String.init) }

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Chip("~", tone: .fill, mono: true)
                            ForEach(Array(crumbs.enumerated()), id: \.offset) { i, c in
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(p.labelTertiary)
                                Chip(c, tone: i == crumbs.count - 1 ? .brand : .fill, mono: true)
                            }
                        }
                    }
                    PaperCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                                Button { open(e) } label: { FileRow(entry: e) }.buttonStyle(.plain)
                                if i < entries.count - 1 { Divider_() }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    if let selected, selected.kind != .folder {
                        PaperCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 10) {
                                    Image(systemName: symbol(for: selected.kind)).foregroundStyle(p.blue)
                                    Text(selected.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(p.label)
                                    Spacer(); Text("预览").font(.yzFootnote).foregroundStyle(p.labelTertiary)
                                }
                                CodeBlock(preview, dark: true, lines: nil)
                                HStack(spacing: 8) {
                                    Button { UIPasteboard.general.string = selected.path; store.toast = "已复制路径" } label: { Label("复制路径", systemImage: "doc.on.doc") }
                                        .buttonStyle(SecondaryButtonStyle(height: 44))
                                    Button { store.toast = "开始下载 \(selected.name)" } label: { Label("下载到手机", systemImage: "arrow.down.to.line") }
                                        .buttonStyle(PrimaryButtonStyle(height: 44))
                                }
                            }
                        }
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "lock").font(.system(size: 11))
                        Text("只预览与下载，手机不会执行任何文件").font(.yzFootnote)
                    }
                    .foregroundStyle(p.labelTertiary).frame(maxWidth: .infinity)
                }
                .padding(16)
            }
        }
        .navigationTitle("文件")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) { Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") } }
        }
        .task { await load() }
    }

    private func load() async {
        guard let session, let device = store.device(session.deviceId) else { entries = MockData.files; return }
        do { entries = try await store.client.listFiles(device: device, sessionId: session.id, path: path) } catch { store.toast = error.localizedDescription }
    }

    private func open(_ e: FileEntry) {
        if e.kind == .folder { path = e.path; Task { await load() }; return }
        selected = e
        Task {
            guard let session, let device = store.device(session.deviceId) else { return }
            preview = (try? await store.client.preview(device: device, sessionId: session.id, path: e.path)) ?? "（无法预览）"
        }
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
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(p.labelSecondary)
                .frame(width: 38, height: 38).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint))
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(p.label).lineLimit(1)
                Text(meta).font(.yzCaption).foregroundStyle(p.labelTertiary)
            }
            Spacer(minLength: 4)
            if let b = entry.badge { Chip(b, tone: b == "审批中" ? .danger : .sage) }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(p.labelTertiary)
        }
        .padding(.horizontal, Spacing.card).frame(minHeight: 60)
    }
    private var meta: String {
        let size = entry.kind == .folder ? "" : ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file) + " · "
        return size + RelativeTime.string(from: entry.modifiedAt)
    }
}
