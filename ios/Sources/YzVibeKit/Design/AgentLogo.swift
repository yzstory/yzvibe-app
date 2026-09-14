import SwiftUI

/// Bundled brand marks; status is represented separately by the session indicator.
struct AgentLogo: View {
    let agent: AgentKind
    var size: CGFloat = 16

    private var asset: String? {
        switch agent {
        case .codex: "AgentCodex"
        case .claude: "AgentClaude"
        case .omp: "AgentOMP"
        default: nil
        }
    }

    var body: some View {
        if let asset {
            Image(asset, bundle: .module)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}
