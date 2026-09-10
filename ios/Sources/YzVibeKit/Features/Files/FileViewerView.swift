import SwiftUI
import UIKit

/// 单个远程文件的查看器：标题是文件名、副标题是完整路径，右上角「下载」与「复制」。
/// 从文件列表点进来，或在聊天正文里点文件路径唤起。手机只读取内容，不执行任何文件。
struct FileViewerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    let session: Session?
    /// 相对工作目录的路径，或绝对路径 / `~/…`
    let path: String

    @State private var info: FileInfo?
    @State private var content: String?
    @State private var image: UIImage?
    @State private var error: String?
    @State private var loading = true
    @State private var downloading = false
    @State private var share: ShareItem?

    private struct ShareItem: Identifiable { let id = UUID(); let url: URL }

    private var fileName: String { info?.name ?? path.split(separator: "/").last.map(String.init) ?? path }

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headline
                    if loading {
                        PaperCard { HStack { Spacer(); ProgressView(); Spacer() }.frame(height: 120) }
                    } else if let error {
                        PaperCard {
                            VStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle").font(.system(.title2)).foregroundStyle(p.amber)
                                Text(error).font(.yzSubhead).foregroundStyle(p.labelSecondary).multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                    } else if let image {
                        PaperCard(padding: 0) {
                            Image(uiImage: image).resizable().scaledToFit()
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    } else if let content {
                        CodeBlock(content, dark: true, lines: nil, language: info?.kind.languageLabel, copyable: true,
                                  onCopy: { _ in store.toast = "已复制文件内容" })
                    }
                    footer
                }
                .padding(16)
            }
        }
        .navigationTitle(fileName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { Task { await download() } } label: {
                    if downloading { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.down.to.line") }
                }
                .disabled(downloading || loading || error != nil)
                Button { copyContent() } label: { Image(systemName: "doc.on.doc") }
                    .disabled(content == nil && image == nil)
            }
        }
        .sheet(item: $share) { ShareSheet(url: $0.url) }
        .task(id: path) { await load() }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(fileName).font(.yzTitle2).foregroundStyle(p.label).lineLimit(2)
            Text(info?.displayPath ?? path)
                .font(.yzMono).foregroundStyle(p.labelSecondary)
                .lineLimit(2).truncationMode(.middle)
                .textSelection(.enabled)
            if let info {
                HStack(spacing: 8) {
                    Chip(info.sizeText, tone: .fill, mono: true)
                    Chip(RelativeTime.string(from: info.modifiedAt), tone: .fill)
                    if !info.inCwd { Chip("工作目录外", tone: .claude) }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock").font(.system(.caption2))
            Text("只读取内容，手机不会执行任何文件").font(.yzFootnote)
        }
        .foregroundStyle(p.labelTertiary).frame(maxWidth: .infinity)
    }

    // MARK: 数据

    private func load() async {
        loading = true; error = nil; content = nil; image = nil
        defer { loading = false }
        guard let session, let device = store.device(session.deviceId) else {
            content = "（演示模式没有真实文件）"; return
        }
        do {
            let meta = try await store.client.fileInfo(device: device, sessionId: session.id, path: path)
            info = meta
            if meta.kind == .image {
                image = UIImage(data: try await store.client.download(device: device, sessionId: session.id, path: meta.path))
                if image == nil { error = "这张图片无法显示，可以下载后再看" }
            } else if meta.textual {
                content = try await store.client.preview(device: device, sessionId: session.id, path: meta.path)
            } else {
                error = "文件超过 2MB，用右上角的下载按钮取回"
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func copyContent() {
        if let content { UIPasteboard.general.string = content; store.toast = "已复制文件内容" }
        else if let image { UIPasteboard.general.image = image; store.toast = "已复制图片" }
    }

    /// 下载到临时目录再用系统分享面板给出去（存文件 / 发给别人 / 拷到别的 App）。
    private func download() async {
        guard let session, let device = store.device(session.deviceId) else { return }
        downloading = true
        defer { downloading = false }
        do {
            let data = try await store.client.download(device: device, sessionId: session.id, path: info?.path ?? path)
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("yzvibe-downloads", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(fileName)
            try data.write(to: url, options: .atomic)
            share = ShareItem(url: url)
        } catch {
            store.toast = "下载失败：\(error.localizedDescription)"
        }
    }
}

/// 系统分享面板（存到「文件」App、隔空投送、发给别人）。
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension FileEntry.Kind {
    /// 代码块标题栏上显示的语言名
    var languageLabel: String {
        switch self {
        case .markdown: "markdown"
        case .code: "code"
        case .image: "image"
        case .folder: "folder"
        case .other: "text"
        }
    }
}
