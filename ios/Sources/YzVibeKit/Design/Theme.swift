import SwiftUI

/// 设计 token（对应 docs/DESIGN.md）。方向 B「焦橙纸感」：暖纸中性 + 单一焦橙强调色。
///
/// 颜色直接用 sRGB hex 定义，和设计文档、`design/directions/build.py` 里的值逐字一致 —— 早期用
/// oklch 换算时文档标注和实际渲染差了整整一档，改成 hex 后两边不会再漂。
/// 每个前景色都标了对最近背景的对比度，改数值时请一并重算（`design/directions/` 里有脚本）。
public struct Palette: Sendable {
    public let brand, brandSoft, brandInk, brandText: Color
    public let sage, sageSoft: Color
    public let amber, amberText, amberSoft: Color
    public let danger, dangerSoft: Color
    public let purple, purpleSoft: Color
    public let blue, blueSoft: Color
    public let surface, surfaceElevated, fill, fillSecondary, border: Color
    public let label, labelSecondary, labelTertiary: Color
    public let shadow: Color

    public static let light = Palette(
        brand: Color(hex: 0xC75015),        // 白字 4.58:1
        brandSoft: Color(hex: 0xFFE5D8),
        brandInk: Color(hex: 0xFFFFFF),
        brandText: Color(hex: 0xA63D02),    // 在 brandSoft 上 5.30:1，在纸底上 5.93:1
        sage: Color(hex: 0x1B7046),         // 纸底 5.65:1
        sageSoft: Color(hex: 0xE0F1E7),
        amber: Color(hex: 0xB0761A),        // 纸底 3.58:1（只做色条与图标，不承载正文）
        amberText: Color(hex: 0x8A5A0E),    // 在 amberSoft 上 5.19:1
        amberSoft: Color(hex: 0xFBEFD6),
        danger: Color(hex: 0xC4261C),       // 纸底 5.35:1，白字 5.77:1
        dangerSoft: Color(hex: 0xFBE3E0),
        purple: Color(hex: 0x6E4B9E), purpleSoft: Color(hex: 0xEFE8F7),
        blue: Color(hex: 0x1F6FA8), blueSoft: Color(hex: 0xE3EFF8),
        surface: Color(hex: 0xF9F6F2),      // 暖纸，不是纯白
        surfaceElevated: Color(hex: 0xFFFDFA),
        fill: Color(hex: 0xEFEAE2), fillSecondary: Color(hex: 0xF4F0E9), border: Color(hex: 0xE6DFD5),
        label: Color(hex: 0x231813),        // 16.09:1
        labelSecondary: Color(hex: 0x6D6059), // 5.62:1
        labelTertiary: Color(hex: 0x877E78),  // 3.69:1（时间戳、占位）
        shadow: Color(hex: 0x50432F)
    )

    /// 深色：暖灰棕底，不用纯黑；橙提亮后配深色文字，而不是白字。
    public static let dark = Palette(
        brand: Color(hex: 0xFF9868),        // 暗底 7.87:1
        brandSoft: Color(hex: 0x3A2A22),
        brandInk: Color(hex: 0x241812),     // 在 brand 上 8.19:1
        brandText: Color(hex: 0xFFB08A),
        sage: Color(hex: 0x5FD08E), sageSoft: Color(hex: 0x23382D),
        amber: Color(hex: 0xE8B45C), amberText: Color(hex: 0xE8B45C), amberSoft: Color(hex: 0x3A3020),
        danger: Color(hex: 0xFF6961), dangerSoft: Color(hex: 0x3A2422),
        purple: Color(hex: 0xC09AE8), purpleSoft: Color(hex: 0x2F2838),
        blue: Color(hex: 0x6FB6E8), blueSoft: Color(hex: 0x22303A),
        surface: Color(hex: 0x201E1B), surfaceElevated: Color(hex: 0x2C2A27),
        fill: Color(hex: 0x383530), fillSecondary: Color(hex: 0x322F2B), border: Color.white.opacity(0.12),
        label: Color(hex: 0xF5F2EE), labelSecondary: Color(hex: 0xB5AEA6), labelTertiary: Color(hex: 0x8A837B),
        shadow: .black
    )

    /// 「增强对比度」辅助功能开关打开时用：压暗次要文字、加深强调色。
    public static let lightHighContrast = Palette(
        brand: Color(hex: 0xA83B00), brandSoft: Color(hex: 0xFFDCCA), brandInk: Color(hex: 0xFFFFFF), brandText: Color(hex: 0x8A3200),
        sage: Color(hex: 0x145A37), sageSoft: Color(hex: 0xD8EEE1),
        amber: Color(hex: 0x8A5A0E), amberText: Color(hex: 0x6E470A), amberSoft: Color(hex: 0xF8E9C8),
        danger: Color(hex: 0xA31A12), dangerSoft: Color(hex: 0xF9D9D5),
        purple: Color(hex: 0x573A7E), purpleSoft: Color(hex: 0xE9DFF4),
        blue: Color(hex: 0x155888), blueSoft: Color(hex: 0xDAE9F5),
        surface: Color(hex: 0xF9F6F2), surfaceElevated: Color(hex: 0xFFFFFF),
        fill: Color(hex: 0xE9E3DA), fillSecondary: Color(hex: 0xF1ECE4), border: Color(hex: 0xC9C0B4),
        label: Color(hex: 0x160E0A), labelSecondary: Color(hex: 0x554A44), labelTertiary: Color(hex: 0x6F675F),
        shadow: Color(hex: 0x50432F)
    )

    public static let darkHighContrast = Palette(
        brand: Color(hex: 0xFFB088), brandSoft: Color(hex: 0x45322A), brandInk: Color(hex: 0x1A100C), brandText: Color(hex: 0xFFC4A6),
        sage: Color(hex: 0x86E0AC), sageSoft: Color(hex: 0x2A4335),
        amber: Color(hex: 0xF2C97F), amberText: Color(hex: 0xF2C97F), amberSoft: Color(hex: 0x453A26),
        danger: Color(hex: 0xFF8B84), dangerSoft: Color(hex: 0x452A28),
        purple: Color(hex: 0xD4B8F2), purpleSoft: Color(hex: 0x392F44),
        blue: Color(hex: 0x94CCF2), blueSoft: Color(hex: 0x2A3A45),
        surface: Color(hex: 0x1A1816), surfaceElevated: Color(hex: 0x2A2724),
        fill: Color(hex: 0x3E3A35), fillSecondary: Color(hex: 0x35322D), border: Color.white.opacity(0.22),
        label: Color(hex: 0xFFFDFA), labelSecondary: Color(hex: 0xCCC5BC), labelTertiary: Color(hex: 0xA9A199),
        shadow: .black
    )

    public static func current(_ scheme: ColorScheme, _ contrast: ColorSchemeContrast = .standard) -> Palette {
        switch (scheme, contrast) {
        case (.dark, .increased): darkHighContrast
        case (.dark, _): dark
        case (_, .increased): lightHighContrast
        default: light
        }
    }
}

public extension Color {
    /// `Color(hex: 0xC75015)`
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

public enum Radius {
    public static let sm: CGFloat = 8, md: CGFloat = 10, lg: CGFloat = 14, xl: CGFloat = 16, xxl: CGFloat = 20, card: CGFloat = 16
}

public enum Spacing {
    public static let page: CGFloat = 20, card: CGFloat = 16, row: CGFloat = 12
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
/// 同时跟随系统的深色模式与「增强对比度」开关。
public struct PaletteProvider<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    let content: () -> Content
    public init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    public var body: some View { content().environment(\.palette, Palette.current(scheme, contrast)) }
}

// MARK: - 字体

/// 全部基于系统文本样式，跟随「动态字体」缩放。需要固定尺寸的地方用 `@ScaledMetric`，不要写死 pt。
public extension Font {
    static let yzLargeTitle = Font.system(.largeTitle, weight: .bold)
    static let yzTitle1 = Font.system(.title, weight: .bold)
    static let yzTitle2 = Font.system(.title2, weight: .semibold)
    static let yzTitle3 = Font.system(.title3, weight: .semibold)
    static let yzHeadline = Font.system(.headline)
    static let yzBody = Font.system(.body)
    static let yzCallout = Font.system(.callout, weight: .semibold)
    static let yzSubhead = Font.system(.subheadline)
    static let yzSubheadStrong = Font.system(.subheadline, weight: .semibold)
    static let yzFootnote = Font.system(.footnote)
    static let yzFootnoteStrong = Font.system(.footnote, weight: .semibold)
    static let yzCaption = Font.system(.caption)
    static let yzEyebrow = Font.system(.caption, weight: .semibold)
    static let yzMono = Font.system(.footnote, design: .monospaced)
    static let yzMonoBody = Font.system(.subheadline, design: .monospaced)
}
