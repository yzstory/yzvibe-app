import SwiftUI

/// 漂浮层材质：iOS 26 走系统 `glassEffect`，更低版本回落到系统材质 + 发丝描边。
///
/// 方向 B 只在真正漂浮的东西上用它 —— 输入条、Toast、扫码取景框。内容一律用 `PaperCard`
/// 或系统 `List`。旧版那层手绘的白色高光渐变已经去掉：它在纯色背景上会显出塑料感，
/// 而系统材质自己就带高光。
public struct LiquidGlass<S: Shape & InsettableShape>: ViewModifier {
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S
    let tint: Color?
    let interactive: Bool

    public func body(content: Content) -> some View {
        // 「降低透明度」打开时给不透明底，否则模糊会让文字读不清
        if reduceTransparency {
            return AnyView(
                content.background {
                    shape.fill(tint ?? p.surfaceElevated)
                        .overlay(shape.strokeBorder(p.border, lineWidth: 1))
                }
            )
        }
        if #available(iOS 26, *) {
            var glass: Glass = .regular
            if let tint { glass = glass.tint(tint) }
            if interactive { glass = glass.interactive() }
            return AnyView(content.glassEffect(glass, in: shape))
        }
        return AnyView(
            content.background {
                shape.fill(.regularMaterial)
                    .overlay(shape.fill(tint?.opacity(0.16) ?? Color.clear))
                    .overlay(shape.strokeBorder(p.border.opacity(0.8), lineWidth: 0.5))
                    .shadow(color: p.shadow.opacity(0.08), radius: 12, y: 6)
            }
        )
    }
}

public extension View {
    func liquidGlass<S: Shape & InsettableShape>(in shape: S = Capsule(), tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(LiquidGlass(shape: shape, tint: tint, interactive: interactive))
    }
}

// MARK: - 按钮样式
//
// 高度用 @ScaledMetric 跟随动态字体；系统的 borderedProminent 没有投影，这里也不加，
// 免得在暖纸底上显出一层「浮起来的塑料」。

/// 主按钮：品牌橙实心 + 白字（4.58:1）。
public struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var p
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var scaled: CGFloat = 1
    var height: CGFloat = 50
    public init(height: CGFloat = 50) { self.height = height }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.yzCallout)
            .foregroundStyle(p.brandInk)
            .frame(maxWidth: .infinity, minHeight: height * scaled)
            .padding(.horizontal, 16)
            .background(Capsule().fill(p.brand).opacity(isEnabled ? 1 : 0.4))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : Motion.quick, value: configuration.isPressed)
    }
}

/// 次按钮：fill 底。
public struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var p
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var scaled: CGFloat = 1
    var height: CGFloat = 50
    public init(height: CGFloat = 50) { self.height = height }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.yzCallout)
            .foregroundStyle(p.label)
            .frame(maxWidth: .infinity, minHeight: height * scaled)
            .padding(.horizontal, 16)
            .background(Capsule().fill(p.fill).opacity(isEnabled ? 1 : 0.5))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : Motion.quick, value: configuration.isPressed)
    }
}

/// 描边按钮（拒绝用 danger 色）。
public struct OutlineButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var p
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var scaled: CGFloat = 1
    var color: Color?
    var height: CGFloat = 50
    public init(color: Color? = nil, height: CGFloat = 50) { self.color = color; self.height = height }
    public func makeBody(configuration: Configuration) -> some View {
        let c = color ?? p.label
        return configuration.label
            .font(.yzCallout)
            .foregroundStyle(c)
            .frame(maxWidth: .infinity, minHeight: height * scaled)
            .padding(.horizontal, 16)
            .background(Capsule().strokeBorder((color ?? p.border).opacity(color == nil ? 1 : 0.5), lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : Motion.quick, value: configuration.isPressed)
    }
}

/// 玻璃按钮：漂浮在内容之上的次级动作。
public struct GlassButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var p
    @ScaledMetric(relativeTo: .body) private var scaled: CGFloat = 1
    var height: CGFloat = 50
    public init(height: CGFloat = 50) { self.height = height }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.yzCallout)
            .foregroundStyle(p.label)
            .frame(maxWidth: .infinity, minHeight: height * scaled)
            .padding(.horizontal, 16)
            .liquidGlass(in: Capsule(), interactive: true)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : Motion.quick, value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == PrimaryButtonStyle { static var yzPrimary: PrimaryButtonStyle { .init() } }
public extension ButtonStyle where Self == SecondaryButtonStyle { static var yzSecondary: SecondaryButtonStyle { .init() } }
public extension ButtonStyle where Self == GlassButtonStyle { static var yzGlass: GlassButtonStyle { .init() } }
