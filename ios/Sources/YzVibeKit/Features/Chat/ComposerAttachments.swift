import SwiftUI
import UIKit
import UniformTypeIdentifiers
import QuickLook

struct PendingFile: Identifiable, Sendable {
    var id = UUID()
    var name: String
    var mime: String
    var data: Data

    static func read(_ url: URL) async throws -> Self {
        try await Task.detached(priority: .userInitiated) {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            var coordinationError: NSError?
            var result: Result<PendingFile, Error>?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { local in
                result = Result {
                    let info = try local.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey])
                    guard info.isRegularFile == true, (info.fileSize ?? 0) <= 20 * 1024 * 1024 else {
                        throw ConnectorError.network("请选择不超过 20 MB 的文件，暂不支持文件夹。")
                    }
                    let data = try Data(contentsOf: local)
                    guard data.count <= 20 * 1024 * 1024 else { throw ConnectorError.network("文件超过 20 MB。") }
                    return PendingFile(name: local.lastPathComponent, mime: info.contentType?.preferredMIMEType ?? "application/octet-stream", data: data)
                }
            }
            if let coordinationError { throw coordinationError }
            guard let result else { throw ConnectorError.network("文件无法读取，请下载到 iPhone 后重试。") }
            return try result.get()
        }.value
    }
}

struct CameraCapture: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera
        picker.cameraCaptureMode = .photo; picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let completion: (UIImage?) -> Void
        init(_ completion: @escaping (UIImage?) -> Void) { self.completion = completion }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            completion(info[.originalImage] as? UIImage)
        }
    }
}

public struct UploadedAttachmentInfo: Decodable, Sendable {
    var name: String
    var mime: String
    var size: Int
}
struct DocumentPreview: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController(); controller.dataSource = context.coordinator; return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(_ url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { url as NSURL }
    }
}

struct UploadedAttachment: View {
    @Environment(AppStore.self) private var store
    let id: String
    let sessionId: String
    let size: CGFloat
    let openImage: (UIImage) -> Void
    @State private var info: UploadedAttachmentInfo?
    @State private var metadataReady = false
    @State private var fileURL: URL?
    @State private var loading = false
    @State private var error: String?
    @State private var preview = false
    var body: some View {
        Button { Task { await open() } } label: {
            if !metadataReady { ProgressView().frame(width: size, height: size) }
            else if let info, !info.mime.hasPrefix("image/") {
                VStack(spacing: 6) {
                    Image(systemName: "doc.fill").font(.title2)
                    Text(info.name).font(.caption).lineLimit(2)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(info.size), countStyle: .file)).font(.caption2)
                    if loading { ProgressView() }
                }.padding(10).frame(width: size, height: size).background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
            } else { AttachmentThumb(id: id, sessionId: sessionId, size: size) }
        }.buttonStyle(.plain)
        .task(id: id) {
            defer { metadataReady = true }
            guard let s = store.session(sessionId), let d = store.device(s.deviceId) else { return }
            info = try? await store.client.attachmentInfo(device: d, id: id)
        }
        .sheet(isPresented: $preview, onDismiss: {
            if let fileURL { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
            fileURL = nil
        }) { if let fileURL { DocumentPreview(url: fileURL) } }
        .alert("无法打开附件", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(error ?? "") }
    }
    private func open() async {
        guard !loading, let s = store.session(sessionId), let d = store.device(s.deviceId) else { return }
        loading = true; defer { loading = false }
        if info == nil { info = try? await store.client.attachmentInfo(device: d, id: id) }
        if let info, !info.mime.hasPrefix("image/") {
            do {
                if fileURL == nil {
                    let data = try await store.client.attachment(device: d, id: id)
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("YzVibeAttachments/\(id)")
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let target = folder.appendingPathComponent(URL(fileURLWithPath: info.name).lastPathComponent)
                    try data.write(to: target, options: .atomic); fileURL = target
                }
                preview = true
            } catch { self.error = "文件读取失败，请检查连接后重试。" }
        } else {
            await store.loadAttachment(id, for: sessionId)
            if let image = store.attachmentImages[id] { openImage(image) }
            else { error = "附件暂时无法读取，请检查连接后重试。" }
        }
    }
}
