import UIKit

/// 上传前的图片处理：长边缩到 1568px（Claude API 会把更大的图缩到这个尺寸，多传只费流量），转成 JPEG。
/// 原图小于阈值时保留原尺寸，只重新编码；无法解码的数据返回 nil，调用方按原样上传。
public enum ImagePrep {
    public static let maxEdge: CGFloat = 1568
    public static let jpegQuality: CGFloat = 0.85

    public static func forUpload(_ data: Data, maxEdge: CGFloat = ImagePrep.maxEdge) async -> (Data, String, String)? {
        await Task.detached(priority: .userInitiated) { () -> (Data, String, String)? in
            guard let out = downscale(data, maxEdge: maxEdge) else { return nil }
            return (out, "image/jpeg", "photo.jpg")
        }.value
    }

    /// 同步版本，便于测试。
    public static func downscale(_ data: Data, maxEdge: CGFloat = ImagePrep.maxEdge) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let longest = max(size.width, size.height)
        let scale = longest > maxEdge ? maxEdge / longest : 1
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: jpegQuality)
    }
}
