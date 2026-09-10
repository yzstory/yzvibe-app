import SwiftUI
import UIKit

/// 全屏看图：双指缩放、双击放大 / 还原、下拉或点关闭退出，可分享。
struct ImageViewer: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            ZoomableImage(image: image).ignoresSafeArea()
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(.subheadline, weight: .bold)).foregroundStyle(.white).frame(width: 40, height: 40).background(Circle().fill(.white.opacity(0.18))) }
                Spacer()
                Text("\(Int(image.size.width)) × \(Int(image.size.height))").font(.yzCaption).monospacedDigit().foregroundStyle(.white.opacity(0.7))
                Spacer()
                ShareLink(item: Image(uiImage: image), preview: SharePreview("图片", image: Image(uiImage: image))) {
                    Image(systemName: "square.and.arrow.up").font(.system(.subheadline, weight: .bold)).foregroundStyle(.white).frame(width: 40, height: 40).background(Circle().fill(.white.opacity(0.18)))
                }
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .statusBarHidden(true)
    }
}

/// UIScrollView 承载的缩放图，比 SwiftUI 手势组合稳定。
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 5
        scroll.showsVerticalScrollIndicator = false; scroll.showsHorizontalScrollIndicator = false
        scroll.backgroundColor = .black
        scroll.contentInsetAdjustmentBehavior = .never
        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFit
        iv.isUserInteractionEnabled = true
        scroll.addSubview(iv)
        context.coordinator.imageView = iv
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        tap.numberOfTapsRequired = 2
        iv.addGestureRecognizer(tap)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.imageView?.frame = scroll.bounds
        scroll.contentSize = scroll.bounds.size
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            // 缩放后保持居中
            guard let iv = imageView else { return }
            let dx = max(0, (scrollView.bounds.width - iv.frame.width) / 2), dy = max(0, (scrollView.bounds.height - iv.frame.height) / 2)
            scrollView.contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
        }
        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            guard let scroll = imageView?.superview as? UIScrollView else { return }
            if scroll.zoomScale > 1.01 { scroll.setZoomScale(1, animated: true); return }
            let point = g.location(in: imageView)
            let size = CGSize(width: scroll.bounds.width / 2.5, height: scroll.bounds.height / 2.5)
            scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }
}
