import SwiftUI
import AVFoundation
import PhotosUI
import CoreImage
import UIKit

/// 全屏扫码：相机取景 + 中央玻璃取景框 + 四角 brand 高光。
struct PairScannerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State private var scanned: PairingPayload?
    @State private var busy = false
    @State private var error: String?
    @State private var showManual = false
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            Color(oklch: 0.18, 0.01, 50).ignoresSafeArea()
            CameraPreview { code in
                guard scanned == nil, !busy else { return }
                if let payload = PairingPayload(text: code) { scanned = payload; Task { await pair(payload) } }
                else { error = "这不是 YzVibe 的配对二维码" }
            }
            .ignoresSafeArea()

            // 遮罩 + 取景框
            Color.black.opacity(0.28).ignoresSafeArea()
                .mask {
                    Rectangle().overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).frame(width: 260, height: 260).blendMode(.destinationOut))
                }
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                .frame(width: 260, height: 260)
                .overlay(ViewfinderCorners(color: p.brand))
                .overlay(ScanLine(color: p.brand))

            VStack {
                HStack {
                    circleButton("xmark") { dismiss() }
                    Spacer()
                    Text("扫码配对").font(.yzHeadline).foregroundStyle(.white)
                    Spacer()
                    PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                        Image(systemName: "photo").font(.system(.callout, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 44, height: 44).background(Circle().fill(.white.opacity(0.12)))
                    }
                    .disabled(busy)
                }
                .padding(.horizontal, 6).padding(.vertical, 6)
                .liquidGlass(in: Capsule())
                .padding(.horizontal, 16)
                Spacer()
                VStack(spacing: 14) {
                    Text(busy ? "正在配对…" : "对准终端里的二维码").font(.yzHeadline).foregroundStyle(.white.opacity(0.9))
                    Text(error ?? "在电脑上运行下面命令后，扫一次即可完成配对").font(.yzSubhead).foregroundStyle(error == nil ? .white.opacity(0.6) : p.danger).multilineTextAlignment(.center)
                    HStack(spacing: 10) {
                        Image(systemName: "terminal").foregroundStyle(p.amber)
                        Text("npx yzvibe").font(.yzMonoBody).foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 28)
                    Button { showManual = true } label: { Label("手动输入 Host / Token", systemImage: "pencil").foregroundStyle(.white) }
                        .buttonStyle(.yzGlass)
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
        }
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $showManual) { ManualEndpointView().presentationDetents([.medium, .large]) }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await scanFromLibrary(item); pickerItem = nil }
        }
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(.callout, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 44, height: 44).background(Circle().fill(.white.opacity(0.12)))
        }
    }

    /// 相册里选一张图，识别其中的二维码后直接配对。
    private func scanFromLibrary(_ item: PhotosPickerItem) async {
        guard !busy else { return }
        error = nil
        busy = true
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            busy = false; error = "读不出这张图片，换一张试试"; return
        }
        guard let code = await QRImageScanner.firstCode(in: data) else {
            busy = false; error = "这张图里没找到二维码，换一张或改用「手动添加 › 粘贴配置」"; return
        }
        guard let payload = PairingPayload(text: code) else {
            busy = false; error = "这不是 YzVibe 的配对二维码"; return
        }
        scanned = payload
        await pair(payload)          // pair 自己管 busy
    }

    private func pair(_ payload: PairingPayload) async {
        busy = true
        do { try await store.pair(payload); dismiss() }
        catch let e { error = e.localizedDescription; scanned = nil }
        busy = false
    }
}

struct ViewfinderCorners: View {
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, r: CGFloat = 20, len: CGFloat = 36
            Path { path in
                path.move(to: CGPoint(x: 0, y: len)); path.addLine(to: CGPoint(x: 0, y: r)); path.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero); path.addLine(to: CGPoint(x: len, y: 0))
                path.move(to: CGPoint(x: w - len, y: 0)); path.addLine(to: CGPoint(x: w - r, y: 0)); path.addQuadCurve(to: CGPoint(x: w, y: r), control: CGPoint(x: w, y: 0)); path.addLine(to: CGPoint(x: w, y: len))
                path.move(to: CGPoint(x: w, y: h - len)); path.addLine(to: CGPoint(x: w, y: h - r)); path.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h)); path.addLine(to: CGPoint(x: w - len, y: h))
                path.move(to: CGPoint(x: len, y: h)); path.addLine(to: CGPoint(x: r, y: h)); path.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h)); path.addLine(to: CGPoint(x: 0, y: h - len))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
        .padding(4)
    }
}

struct ScanLine: View {
    let color: Color
    @State private var y: CGFloat = -110
    var body: some View {
        LinearGradient(colors: [.clear, color, .clear], startPoint: .leading, endPoint: .trailing)
            .frame(width: 220, height: 2)
            .offset(y: y)
            .onAppear { withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { y = 110 } }
    }
}

/// AVFoundation 相机 + 二维码识别。模拟器无相机时显示占位。
struct CameraPreview: UIViewRepresentable {
    var onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        context.coordinator.configure(on: view)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onCode: (String) -> Void
        let session = AVCaptureSession()
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func configure(on view: PreviewView) {
            guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device) else { return }
            nonisolated(unsafe) let session = self.session
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted, let self else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    session.beginConfiguration()
                    if session.canAddInput(input) { session.addInput(input) }
                    let output = AVCaptureMetadataOutput()
                    if session.canAddOutput(output) {
                        session.addOutput(output)
                        output.setMetadataObjectsDelegate(self, queue: .main)
                        output.metadataObjectTypes = [.qr]
                    }
                    session.commitConfiguration()
                    DispatchQueue.main.async {
                        view.previewLayer.session = session
                        view.previewLayer.videoGravity = .resizeAspectFill
                    }
                    session.startRunning()
                }
            }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard let obj = objects.first as? AVMetadataMachineReadableCodeObject, let s = obj.stringValue else { return }
            onCode(s)
        }
    }
}

/// 从图片里识别二维码（相册选图配对用）。取内容最长的一个，避免截图里夹带其它小码。
enum QRImageScanner {
    /// 识别放到后台线程，避免大图卡住界面。
    static func firstCode(in data: Data) async -> String? {
        await Task.detached(priority: .userInitiated) { decode(data) }.value
    }

    static func decode(_ data: Data) -> String? {
        guard let image = UIImage(data: data), let cg = image.cgImage else { return nil }
        return firstCode(in: CIImage(cgImage: cg))
    }

    static func firstCode(in image: CIImage) -> String? {
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let codes = (detector?.features(in: image) as? [CIQRCodeFeature] ?? [])
            .compactMap(\.messageString)
            .filter { !$0.isEmpty }
        if let best = codes.max(by: { $0.count < $1.count }) { return best }
        // 有些截图的二维码偏小或对比度低，放大一倍再试一次
        let scaled = image.transformed(by: CGAffineTransform(scaleX: 2, y: 2))
        guard scaled.extent.width <= 8000, scaled.extent.height <= 8000 else { return nil }
        return (detector?.features(in: scaled) as? [CIQRCodeFeature] ?? [])
            .compactMap(\.messageString)
            .filter { !$0.isEmpty }
            .max(by: { $0.count < $1.count })
    }
}
