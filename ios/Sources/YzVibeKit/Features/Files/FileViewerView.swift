import SwiftUI
import UIKit
import AVKit
import Combine

/// 单个远程文件的查看器：标题是文件名、副标题是完整路径，右上角「下载」与「复制」。
/// 从文件列表点进来，或在聊天正文里点文件路径唤起。HTML 在隔离网页视图中预览，其余文件按类型只读展示。
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
    @State private var localFile: URL?
    @State private var player: AVPlayer?
    @State private var showSource = false
    @State private var showImage = false
    @State private var htmlError: String?
    @State private var openedFile: FileRef?

    private struct ShareItem: Identifiable { let id = UUID(); let url: URL }

    private var fileName: String { info?.name ?? path.split(separator: "/").last.map(String.init) ?? path }

    private var isHTML: Bool { ["html", "htm"].contains(((info?.name ?? path) as NSString).pathExtension.lowercased()) }

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
                                Button("重新加载") { Task { await load() } }
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                    } else if let player {
                        if let item = player.currentItem {
                            VideoPlayer(player: player).frame(height: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .onReceive(item.publisher(for: \.status).receive(on: RunLoop.main)) { status in
                                    if status == .failed { error = "视频无法播放，可使用下载按钮交给其他播放器" }
                                }
                        }
                    } else if let image {
                        Button { showImage = true } label: {
                        PaperCard(padding: 0) {
                            Image(uiImage: image).resizable().scaledToFit()
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        }.buttonStyle(.plain).accessibilityLabel("全屏查看图片")
                    } else if let content {
                        if isHTML && !showSource, let session, let device = store.device(session.deviceId) {
                            if let htmlError { Text(htmlError).font(.yzFootnote).foregroundStyle(p.danger) }
                            let client = store.client
                            let entry = info?.path ?? path
                            HTMLPreview(entry: entry, resource: { resource in
                                try await client.webResource(device: device, sessionId: session.id, entry: entry, resource: resource)
                            }, onError: { htmlError = $0 })
                            .frame(height: 560)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .id(entry)
                        } else if info?.kind == .markdown && !showSource {
                            PaperCard {
                                MarkdownText(text: content, onOpenFile: { openedFile = FileRef(path: $0) },
                                             onCopy: { _ in store.toast = "已复制" }, sessionId: session?.id,
                                             baseDirectory: ((info?.path ?? path) as NSString).deletingLastPathComponent)
                            }
                        } else {
                        CodeBlock(content, dark: true, lines: nil, language: info?.kind.languageLabel, copyable: true,
                                  onCopy: { _ in store.toast = "已复制文件内容" })
                        }
                    } else if let localFile {
                        DocumentPreview(url: localFile).frame(minHeight: 440)
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
                if (info?.kind == .markdown || isHTML), content != nil {
                    Button { showSource.toggle() } label: { Image(systemName: showSource ? "doc.richtext" : "chevron.left.forwardslash.chevron.right") }
                        .accessibilityLabel(showSource ? "查看渲染结果" : "查看源码")
                }
                Button { Task { await download() } } label: {
                    if downloading { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.down.to.line") }
                }
                .disabled(downloading || loading || info == nil)
                Button { copyContent() } label: { Image(systemName: "doc.on.doc") }
                    .disabled(content == nil && image == nil)
            }
        }
        .sheet(item: $share) { ShareSheet(url: $0.url) }
        .fullScreenCover(isPresented: $showImage) { if let image { ImageViewer(image: image) } }
        .navigationDestination(item: $openedFile) { ref in FileViewerView(session: session, path: ref.path) }
        .task(id: path) { await load() }
        .onDisappear { player?.pause(); if share == nil { removeLocalFile() } }
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
            Text(isHTML ? "隔离预览页面 · 支持同目录资源和页面交互" : "只读取内容，手机不会执行任何文件").font(.yzFootnote)
        }
        .foregroundStyle(p.labelTertiary).frame(maxWidth: .infinity)
    }

    // MARK: 数据

    private func load() async {
        loading = true; error = nil; htmlError = nil; showSource = false; content = nil; image = nil; info = nil
        player?.pause(); player = nil; removeLocalFile()
        defer { loading = false }
        guard let session, let device = store.device(session.deviceId) else {
            content = "（演示模式没有真实文件）"; return
        }
        do {
            let meta = try await store.client.fileInfo(device: device, sessionId: session.id, path: path)
            info = meta
            if meta.textual {
                content = try await store.client.preview(device: device, sessionId: session.id, path: meta.path)
            } else if meta.kind == .video || meta.kind == .image || meta.mime == "application/pdf" {
                let url = try await store.client.downloadFile(device: device, sessionId: session.id, path: meta.path)
                localFile = url
                try Task.checkCancellation()
                if meta.kind == .video {
                    let asset = AVURLAsset(url: url)
                    guard try await asset.load(.isPlayable) else { throw ConnectorError.network("iPhone 不支持此视频编码，可使用下载按钮交给其他播放器") }
                    try Task.checkCancellation()
                    let video = AVPlayer(playerItem: AVPlayerItem(asset: asset)); player = video; video.play()
                } else if meta.kind == .image, let decoded = UIImage(contentsOfFile: url.path) { image = decoded }
                // SVG and other native document formats use Quick Look if UIImage cannot decode them.
            } else {
                error = "此文件暂不支持内嵌预览，可以用右上角下载按钮打开"
            }
        } catch is CancellationError {
            removeLocalFile()

        } catch {
            self.error = error.localizedDescription
        }
    }

    private func removeLocalFile() {
        if let localFile {
            let dir = localFile.deletingLastPathComponent()
            if dir.lastPathComponent.hasPrefix("yzvibe-file-") { try? FileManager.default.removeItem(at: dir) }
        }
        localFile = nil
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
            let url: URL
            if let localFile, FileManager.default.fileExists(atPath: localFile.path) { url = localFile }
            else {
                url = try await store.client.downloadFile(device: device, sessionId: session.id, path: info?.path ?? path)
                localFile = url
            }
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
        case .video: "video"
        case .folder: "folder"
        case .other: "text"
        }
    }
}
