import ActivityKit
import SwiftUI
import WidgetKit
import YzVibeKit

@main
struct YzVibeWidgetsBundle: WidgetBundle {
    var body: some Widget { SessionLiveActivity() }
}

/// 锁屏 / 灵动岛上的会话状态：在跑什么、要不要你批、排了几条。
struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color(red: 0.13, green: 0.12, blue: 0.11))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.agent, systemImage: "desktopcomputer")
                        .font(.caption).foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StatusPill(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.headline).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        FooterLine(context: context)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.symbol).foregroundStyle(tint(context.state))
            } compactTrailing: {
                if context.state.needsApproval {
                    Text("\(max(1, context.state.pendingApprovals))").font(.caption2).bold().foregroundStyle(tint(context.state))
                } else if context.state.isRunning {
                    ProgressView().controlSize(.mini)
                }
            } minimal: {
                Image(systemName: context.state.symbol).foregroundStyle(tint(context.state))
            }
            .keylineTint(tint(context.state))
        }
    }

    private func tint(_ s: SessionActivityAttributes.ContentState) -> Color {
        s.needsApproval ? Color(red: 0.85, green: 0.33, blue: 0.27) : s.isRunning ? Color(red: 0.90, green: 0.72, blue: 0.35) : Color(red: 0.40, green: 0.66, blue: 0.55)
    }
}

private struct StatusPill: View {
    let state: SessionActivityAttributes.ContentState
    var body: some View {
        Text(state.shortStatus)
            .font(.caption2).bold()
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(.white.opacity(0.14)))
    }
}

private struct FooterLine: View {
    let context: ActivityViewContext<SessionActivityAttributes>
    var body: some View {
        HStack(spacing: 10) {
            Text(context.attributes.folder).font(.caption2).monospaced().lineLimit(1).truncationMode(.head)
            Spacer(minLength: 4)
            if context.state.queued > 0 { Label("\(context.state.queued)", systemImage: "clock").font(.caption2) }
            if let c = context.state.contextPercent { Text("上下文 \(c)%").font(.caption2) }
        }
        .foregroundStyle(.tertiary)
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<SessionActivityAttributes>
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: context.state.symbol)
                .font(.title3)
                .foregroundStyle(context.state.needsApproval ? Color(red: 0.9, green: 0.45, blue: 0.38) : .white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(.white.opacity(0.12)))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(context.attributes.title).font(.headline).lineLimit(1)
                    Spacer()
                    StatusPill(state: context.state)
                }
                Text(context.state.headline).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                FooterLine(context: context)
            }
        }
        .padding(14)
    }
}
