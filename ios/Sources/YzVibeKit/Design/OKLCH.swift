import SwiftUI

/// oklch → sRGB 转换，让 iOS 端与 docs/DESIGN.md 里的 token 数值逐一对应。
public struct OKLCH: Hashable, Sendable {
    public var l: Double   // 0…1
    public var c: Double   // 0…0.4
    public var h: Double   // 0…360
    public var alpha: Double

    public init(_ l: Double, _ c: Double, _ h: Double, alpha: Double = 1) {
        self.l = l; self.c = c; self.h = h; self.alpha = alpha
    }

    /// 线性 sRGB 分量（未 gamma），可能越界，由 `srgb` 裁剪。
    public var linearRGB: (r: Double, g: Double, b: Double) {
        let hr = h * .pi / 180
        let a = c * cos(hr)
        let b = c * sin(hr)
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let l3 = l_ * l_ * l_, m3 = m_ * m_ * m_, s3 = s_ * s_ * s_
        return (
            r: 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
            g: -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
            b: -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3
        )
    }

    /// gamma 编码并裁剪到 0…1 的 sRGB。
    public var srgb: (r: Double, g: Double, b: Double) {
        func gamma(_ x: Double) -> Double {
            let v = min(max(x, 0), 1)
            return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
        }
        let lin = linearRGB
        return (gamma(lin.r), gamma(lin.g), gamma(lin.b))
    }

    public var color: Color {
        let s = srgb
        return Color(.sRGB, red: s.r, green: s.g, blue: s.b, opacity: alpha)
    }
}

public extension Color {
    /// `Color(oklch: 0.64, 0.17, 40)` —— 与设计规范同一套写法。
    init(oklch l: Double, _ c: Double, _ h: Double, alpha: Double = 1) {
        self = OKLCH(l, c, h, alpha: alpha).color
    }
}
