import SwiftUI

/// A small, truthful waiting state. No artificial progress or delay before showing content.
struct PomeloLoadingView: View {
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    @State private var floating = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Ellipse().fill(p.brand.opacity(0.12)).frame(width: 40, height: 7).offset(y: 36)
                    .scaleEffect(floating && !reduceMotion ? 0.8 : 1)
                BrandLogo(size: 56)
                    .rotationEffect(.degrees(reduceMotion ? 0 : floating ? 3 : -3))
                    .offset(y: reduceMotion ? 0 : floating ? -5 : 0)
            }.frame(height: 76)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(p.brand)
                Text(title).font(.yzFootnote).foregroundStyle(p.labelSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore).accessibilityLabel(title)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { floating = true }
        }
    }
}

/// First-launch hello: arrive, sparkle, pause long enough to read, then fade out.
struct PomeloWelcomeView: View {
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let finish: () -> Void
    @State private var arrived = false
    @State private var spark = false

    var body: some View {
        ZStack {
            p.surface.ignoresSafeArea()
            VStack(spacing: 22) {
                ZStack(alignment: .topTrailing) {
                    BrandLogo(size: 112)
                        .scaleEffect(arrived || reduceMotion ? 1 : 0.65)
                        .rotationEffect(.degrees(arrived || reduceMotion ? 0 : -12))
                        .offset(y: arrived || reduceMotion ? 0 : 20)
                    Image(systemName: "sparkle").font(.system(size: 24, weight: .semibold)).foregroundStyle(p.brand)
                        .offset(x: 15, y: -12).scaleEffect(spark ? 1 : 0.4).opacity(spark ? 1 : 0)
                }
                VStack(spacing: 6) {
                    Text("YzVibe").font(.system(.title, design: .rounded, weight: .bold)).foregroundStyle(p.label)
                    Text("小柚子就位，开工。").font(.yzFootnote).foregroundStyle(p.labelSecondary)
                }.opacity(arrived ? 1 : 0)
            }
        }
        .contentShape(Rectangle()).onTapGesture(perform: finish)
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
        .accessibilityHint("轻点进入")
        .task {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.5, dampingFraction: 0.75)) { arrived = true }
            do {
                try await Task.sleep(for: .milliseconds(500))
                withAnimation(.easeOut(duration: 0.25)) { spark = true }
                // Preserve reading time with Reduce Motion too; only the movement changes.
                try await Task.sleep(for: .milliseconds(1700))
                finish()
            } catch { }
        }
    }
}
