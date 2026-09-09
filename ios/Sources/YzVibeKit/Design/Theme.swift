import SwiftUI

/// 设计 token（对应 docs/DESIGN.md §2–§4）。浅/深色各一组，通过 `Environment(\.colorScheme)` 选择。
public struct Palette: Sendable {
    public let brand, brandSoft, brandInk: Color
    public let sage, sageSoft: Color
    public let amber, amberText, amberSoft: Color
    public let danger, dangerSoft: Color
    public let purple, purpleSoft: Color
    public let blue, blueSoft: Color
    public let surface, surfaceElevated, fill, fillSecondary, border: Color
    public let label, labelSecondary, labelTertiary: Color
    public let orbAlpha: Double
    public let shadow: Color

    public static let light = Palette(
        brand: Color(oklch: 0.64, 0.17, 40), brandSoft: Color(oklch: 0.94, 0.04, 45), brandInk: Color(oklch: 0.99, 0.01, 80),
        sage: Color(oklch: 0.60, 0.09, 165), sageSoft: Color(oklch: 0.93, 0.035, 165),
        amber: Color(oklch: 0.82, 0.13, 80), amberText: Color(oklch: 0.58, 0.12, 70), amberSoft: Color(oklch: 0.96, 0.05, 85),
        danger: Color(oklch: 0.60, 0.20, 25), dangerSoft: Color(oklch: 0.95, 0.04, 25),
        purple: Color(oklch: 0.55, 0.15, 310), purpleSoft: Color(oklch: 0.94, 0.04, 310),
        blue: Color(oklch: 0.58, 0.13, 235), blueSoft: Color(oklch: 0.94, 0.04, 235),
        surface: Color(oklch: 0.975, 0.009, 80), surfaceElevated: Color(oklch: 0.995, 0.004, 85),
        fill: Color(oklch: 0.935, 0.012, 75), fillSecondary: Color(oklch: 0.958, 0.01, 78), border: Color(oklch: 0.90, 0.014, 70),
        label: Color(oklch: 0.22, 0.02, 45), labelSecondary: Color(oklch: 0.50, 0.02, 55), labelTertiary: Color(oklch: 0.68, 0.018, 60),
        orbAlpha: 0.85, shadow: Color(oklch: 0.30, 0.03, 50)
    )

    public static let dark = Palette(
        brand: Color(oklch: 0.72, 0.15, 42), brandSoft: Color(oklch: 0.30, 0.06, 40), brandInk: Color(oklch: 0.16, 0.02, 40),
        sage: Color(oklch: 0.70, 0.09, 165), sageSoft: Color(oklch: 0.28, 0.04, 165),
        amber: Color(oklch: 0.85, 0.12, 82), amberText: Color(oklch: 0.85, 0.12, 82), amberSoft: Color(oklch: 0.30, 0.05, 80),
        danger: Color(oklch: 0.70, 0.18, 25), dangerSoft: Color(oklch: 0.30, 0.06, 25),
        purple: Color(oklch: 0.70, 0.14, 310), purpleSoft: Color(oklch: 0.30, 0.05, 310),
        blue: Color(oklch: 0.70, 0.12, 235), blueSoft: Color(oklch: 0.30, 0.05, 235),
        surface: Color(oklch: 0.16, 0.008, 60), surfaceElevated: Color(oklch: 0.215, 0.01, 60),
        fill: Color(oklch: 0.29, 0.012, 60), fillSecondary: Color(oklch: 0.25, 0.01, 60), border: Color.white.opacity(0.09),
        label: Color(oklch: 0.96, 0.008, 80), labelSecondary: Color(oklch: 0.72, 0.015, 70), labelTertiary: Color(oklch: 0.52, 0.012, 60),
        orbAlpha: 0.35, shadow: .black
    )

    public static func current(_ scheme: ColorScheme) -> Palette { scheme == .dark ? .dark : .light }
}

public enum Radius {
    public static let sm: CGFloat = 10, md: CGFloat = 14, lg: CGFloat = 18, xl: CGFloat = 22, xxl: CGFloat = 26, card: CGFloat = 24
}

public enum Spacing {
    public static let page: CGFloat = 20, card: CGFloat = 18, row: CGFloat = 12
}

public enum Motion {
    public static let quick = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.22)
    public static let drawer = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.4)
}

// MARK: - Environment

private struct PaletteKey: EnvironmentKey { static let defaultValue: Palette = .light }
public extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// 在根视图挂一次，之后子视图用 `@Environment(\.palette) private var p`。
public struct PaletteProvider<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: () -> Content
    public init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    public var body: some View { content().environment(\.palette, Palette.current(scheme)) }
}

// MARK: - Typography (iOS 字阶 + 设计规范)

public extension Font {
    static let yzLargeTitle = Font.system(size: 34, weight: .bold, design: .default)
    static let yzTitle1 = Font.system(size: 28, weight: .bold)
    static let yzTitle2 = Font.system(size: 22, weight: .semibold)
    static let yzHeadline = Font.system(size: 17, weight: .semibold)
    static let yzBody = Font.system(size: 17)
    static let yzCallout = Font.system(size: 16, weight: .semibold)
    static let yzSubhead = Font.system(size: 15)
    static let yzFootnote = Font.system(size: 13)
    static let yzCaption = Font.system(size: 12)
    static let yzEyebrow = Font.system(size: 12, weight: .semibold)
    static let yzMono = Font.system(size: 13, design: .monospaced)
    static let yzMonoBody = Font.system(size: 15, design: .monospaced)
}
