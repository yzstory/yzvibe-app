import SwiftUI

/// 黑曜石与橙色：中性内容层、温暖动作色，玻璃层沿用系统材质。
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
        brand: Color(hex: 0xC04B00),
        brandSoft: Color(hex: 0xFFF0E3),
        brandInk: Color(hex: 0xFFFFFF),
        brandText: Color(hex: 0xA64000),
        sage: Color(hex: 0x1B7046),
        sageSoft: Color(hex: 0xE0F1E7),
        amber: Color(hex: 0xB0761A),
        amberText: Color(hex: 0x8A5A0E),
        amberSoft: Color(hex: 0xFBEFD6),
        danger: Color(hex: 0xC4261C),
        dangerSoft: Color(hex: 0xFBE3E0),
        purple: Color(hex: 0x6E4B9E), purpleSoft: Color(hex: 0xEFE8F7),
        blue: Color(hex: 0x1F6FA8), blueSoft: Color(hex: 0xE3EFF8),
        surface: Color(hex: 0xF6F6F7),
        surfaceElevated: Color(hex: 0xFFFFFF),
        fill: Color(hex: 0xE9E9EB), fillSecondary: Color(hex: 0xF0F0F2), border: Color(hex: 0xDEDEE2),
        label: Color(hex: 0x19191B),
        labelSecondary: Color(hex: 0x606065),
        labelTertiary: Color(hex: 0x79797F),
        shadow: Color(hex: 0x19191B)
    )

    /// 深色：近黑页面、炭灰内容面与明亮的橙色动作。
    public static let dark = Palette(
        brand: Color(hex: 0xFF9A52),
        brandSoft: Color(hex: 0x352419),
        brandInk: Color(hex: 0x261305),
        brandText: Color(hex: 0xFFB57D),
        sage: Color(hex: 0x5FD08E), sageSoft: Color(hex: 0x23382D),
        amber: Color(hex: 0xE8B45C), amberText: Color(hex: 0xE8B45C), amberSoft: Color(hex: 0x3A3020),
        danger: Color(hex: 0xFF6961), dangerSoft: Color(hex: 0x3A2422),
        purple: Color(hex: 0xC09AE8), purpleSoft: Color(hex: 0x2F2838),
        blue: Color(hex: 0x6FB6E8), blueSoft: Color(hex: 0x22303A),
        surface: Color(hex: 0x0B0B0D), surfaceElevated: Color(hex: 0x19191D),
        fill: Color(hex: 0x2D2D32), fillSecondary: Color(hex: 0x222226), border: Color.white.opacity(0.12),
        label: Color(hex: 0xF5F5F7), labelSecondary: Color(hex: 0xB9B9C0), labelTertiary: Color(hex: 0x92929C),
        shadow: .black
    )

    /// 「增强对比度」辅助功能开关打开时用：压暗次要文字、加深强调色。
    public static let lightHighContrast = Palette(
        brand: Color(hex: 0xA73D00), brandSoft: Color(hex: 0xFFE5CE), brandInk: Color(hex: 0xFFFFFF), brandText: Color(hex: 0x863100),
        sage: Color(hex: 0x145A37), sageSoft: Color(hex: 0xD8EEE1),
        amber: Color(hex: 0x8A5A0E), amberText: Color(hex: 0x6E470A), amberSoft: Color(hex: 0xF8E9C8),
        danger: Color(hex: 0xA31A12), dangerSoft: Color(hex: 0xF9D9D5),
        purple: Color(hex: 0x573A7E), purpleSoft: Color(hex: 0xE9DFF4),
        blue: Color(hex: 0x155888), blueSoft: Color(hex: 0xDAE9F5),
        surface: Color(hex: 0xF6F6F7), surfaceElevated: Color(hex: 0xFFFFFF),
        fill: Color(hex: 0xE4E4E7), fillSecondary: Color(hex: 0xEFEFF1), border: Color(hex: 0xBDBDC5),
        label: Color(hex: 0x111113), labelSecondary: Color(hex: 0x49494F), labelTertiary: Color(hex: 0x626269),
        shadow: Color(hex: 0x19191B)
    )

    public static let darkHighContrast = Palette(
        brand: Color(hex: 0xFFB078), brandSoft: Color(hex: 0x3D281A), brandInk: Color(hex: 0x1F0F02), brandText: Color(hex: 0xFFCAA3),
        sage: Color(hex: 0x86E0AC), sageSoft: Color(hex: 0x2A4335),
        amber: Color(hex: 0xF2C97F), amberText: Color(hex: 0xF2C97F), amberSoft: Color(hex: 0x453A26),
        danger: Color(hex: 0xFF8B84), dangerSoft: Color(hex: 0x452A28),
        purple: Color(hex: 0xD4B8F2), purpleSoft: Color(hex: 0x392F44),
        blue: Color(hex: 0x94CCF2), blueSoft: Color(hex: 0x2A3A45),
        surface: Color(hex: 0x030304), surfaceElevated: Color(hex: 0x141417),
        fill: Color(hex: 0x303035), fillSecondary: Color(hex: 0x242429), border: Color.white.opacity(0.22),
        label: Color(hex: 0xFFFFFF), labelSecondary: Color(hex: 0xD6D6DC), labelTertiary: Color(hex: 0xB8B8C2),
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
    /// `Color(hex: 0xC04B00)`
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

public enum Radius {
    public static let sm: CGFloat = 8, md: CGFloat = 10, lg: CGFloat = 14, xl: CGFloat = 16, xxl: CGFloat = 28, card: CGFloat = 26
}

public enum Spacing {
    public static let page: CGFloat = 20, card: CGFloat = 16, row: CGFloat = 12
}

public enum Motion {
    public static let quick = Animation.spring(response: 0.28, dampingFraction: 1)
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
