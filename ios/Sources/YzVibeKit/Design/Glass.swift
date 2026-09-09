import SwiftUI

/// 液态玻璃：iOS 26 走系统 `glassEffect`，更低版本回落到材质模糊 + 高光描边。
/// 只用于「漂浮层」——输入条、审批卡、浮动按钮、连接胶囊；内容卡片请用 `PaperCard`。
public struct LiquidGlass<S: Shape & InsettableShape>: ViewModifier {
    @Environment(\.palette) private var p
    let shape: S
    let tint: Color?
    let interactive: Bool

    public func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            var glass: Glass = .regular
            if let tint { glass = glass.tint(tint) }
            if interactive { glass = glass.interactive() }
            return AnyView(content.glassEffect(glass, in: shape))
        } else {
            return AnyView(
                content
                    .background {
                        shape.fill(.ultraThinMaterial)
                            .overlay(shape.fill(tint?.opacity(0.18) ?? Color.clear))
                            .overlay(
                                shape.strokeBorder(
                                    LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.12)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                    lineWidth: 0.6
                                )
                            )
                            .shadow(color: p.shadow.opacity(0.10), radius: 15, y: 10)
                    }
            )
        }
    }
}

public extension View {
    func liquidGlass<S: Shape & InsettableShape>(in shape: S = Capsule(), tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(LiquidGlass(shape: shape, tint: tint, interactive: interactive))
    }
    func glassCard(cornerRadius: CGFloat = Radius.xl) -> some View {
        liquidGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// 多个玻璃元素靠近时融合（iOS 26 GlassEffectContainer），旧系统原样输出。
public struct GlassGroup<Content: View>: View {
    let spacing: CGFloat
    let content: () -> Content
    public init(spacing: CGFloat = 12, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing; self.content = content
    }
    public var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

// MARK: - 按钮样式

/// 主按钮：赭红实心；iOS 26 用 glassProminent 叠加 brand tint。
public struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.palette) private var p
    var height: CGFloat = 50
    public init(height: CGFloat = 50) { self.height = height }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.yzCallout)
            .foregroundStyle(p.brandInk)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, 16)
            .background(
                Capsule().fill(p.brand)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.6).blendMode(.plusLighter))
                    .shadow(color: p.brand.opacity(0.32), radius: 11, y: 8)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

/// 次按钮：fill 底。
public struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.palette) private var p
    var height: CGFloat = 50
    public init(height: CGFloat = 50) { self.height = height }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.yzCallout)
            .foregroundStyle(p.label)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, 16)
            .background(Capsule().fill(p.fill))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

/// 描边按钮（拒绝用 danger 色）。
public struct OutlineButtonStyle: ButtonStyle {
    @Environment(\.palette) private var p
    var color: Color?
    var height: CGFloat = 50
    public init(color: Color? = nil, height: CGFloat = 50) { self.color = color; self.height = height }
    public func makeBody(configuration: Configuration) -> some View {
        let c = color ?? p.label
        return configuration.label
            .font(.yzCallout)
            .foregroundStyle(c)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, 16)
            .background(Capsule().strokeBorder((color ?? p.border).opacity(color == nil ? 1 : 0.55), lineWidth: 1.5))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

/// 玻璃按钮：漂浮在装饰球上的次级动作。
public struct GlassButtonStyle: ButtonStyle {
    @Environment(\.palette) private var p
    var height: CGFloat = 50
    public init(height: CGFloat = 50) { self.height = height }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.yzCallout)
            .foregroundStyle(p.label)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, 16)
            .liquidGlass(in: Capsule(), interactive: true)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == PrimaryButtonStyle { static var yzPrimary: PrimaryButtonStyle { .init() } }
public extension ButtonStyle where Self == SecondaryButtonStyle { static var yzSecondary: SecondaryButtonStyle { .init() } }
public extension ButtonStyle where Self == GlassButtonStyle { static var yzGlass: GlassButtonStyle { .init() } }
