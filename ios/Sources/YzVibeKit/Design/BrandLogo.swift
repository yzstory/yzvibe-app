import SwiftUI

/// App 与 Widget 共用 E4 小柚子原图，由 Swift Package 资源包加载。
public struct BrandLogo: View {
    private let size: CGFloat

    public init(size: CGFloat) {
        self.size = size
    }

    public var body: some View {
        Image("BrandLogo", bundle: .module)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .accessibilityLabel("YzVibe")
    }
}
