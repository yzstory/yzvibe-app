import SwiftUI
import UIKit

enum MessageImageLinks {
    enum Part { case text(String), image(String, String) }
    static func parts(_ text: String) -> [Part] {
        guard let regex = try? NSRegularExpression(pattern: #"!?\[([^\]]*)\]\(\s*(<[^>]+>|[^\s)]+)\s*\)"#) else { return [.text(text)] }
        let source = text as NSString
        var parts: [Part] = [], cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            var path = source.substring(with: match.range(at: 2))
            if path.hasPrefix("<"), path.hasSuffix(">") { path = String(path.dropFirst().dropLast()) }
            let url = URL(string: path)
            guard url?.scheme == nil || ["http", "https"].contains(url?.scheme ?? ""),
                  ["png", "jpg", "jpeg", "webp", "gif", "heic"].contains((url?.path ?? path).components(separatedBy: ".").last?.lowercased() ?? "") else { continue }
            if match.range.location > cursor { parts.append(.text(source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))) }
            parts.append(.image(source.substring(with: match.range(at: 1)), path))
            cursor = NSMaxRange(match.range)
        }
        if cursor < source.length { parts.append(.text(source.substring(from: cursor))) }
        return parts
    }
}

/// 图片链接在回复里直接展示；本地路径通过会话所属连接器读取。
struct ReplyImage: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    let title: String
    let path: String
    let sessionId: String
    @State private var image: UIImage?
    @State private var failed = false
    @State private var loading = false
    @State private var presented: Preview?
    private struct Preview: Identifiable { let id = UUID(); let image: UIImage }

    var body: some View {
        Button {
            if let image { presented = Preview(image: image) }
            else { Task { await load() } }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 260)
                    } else {
                        VStack(spacing: 8) {
                            if failed { Image(systemName: "photo.badge.exclamationmark"); Text("图片加载失败，点按重试").font(.yzCaption) }
                            else { ProgressView() }
                        }
                        .frame(height: 140)
                    }
                }
                .frame(maxWidth: .infinity)
                .background(p.fillSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                if !title.isEmpty { Text(title).font(.yzCaption).foregroundStyle(p.labelSecondary) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title.isEmpty ? "查看图片" : "查看图片：\(title)")
        .task(id: path) { await load() }
        .fullScreenCover(item: $presented) { ImageViewer(image: $0.image) }
    }

    private func load() async {
        guard !loading, image == nil else { return }
        loading = true; failed = false
        defer { loading = false }
        do {
            let data: Data
            if let url = URL(string: path), ["http", "https"].contains(url.scheme ?? "") {
                let (body, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw ConnectorError.network("图片请求失败") }
                data = body
            } else {
                guard let session = store.session(sessionId), let device = store.device(session.deviceId) else { throw ConnectorError.badURL }
                data = try await store.client.download(device: device, sessionId: sessionId, path: path.removingPercentEncoding ?? path)
            }
            guard let decoded = UIImage(data: data) else { throw ConnectorError.decoding }
            image = decoded
        } catch is CancellationError { }
        catch { failed = true }
    }
}
