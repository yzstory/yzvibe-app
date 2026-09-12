import ActivityKit
import SwiftUI
import WidgetKit
import YzVibeKit

@main
struct YzVibeWidgetsBundle: WidgetBundle {
    var body: some Widget { SessionLiveActivity() }
}

private let orange = Color(red: 1, green: 0.58, blue: 0.28)

struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    BrandLogo(size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.headline).font(.subheadline.bold())
                        Text(context.attributes.deviceName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    RunningSignal(state: context.state, stale: context.isStale)
                }
                TaskRows(context: context)
            }
            .padding(14)
            .activityBackgroundTint(Color(red: 0.075, green: 0.07, blue: 0.065))
            .activitySystemActionForegroundColor(.white)
            .widgetURL(overviewURL(context.attributes))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { BrandLogo(size: 26) }
                DynamicIslandExpandedRegion(.trailing) {
                    RunningSignal(state: context.state, stale: context.isStale)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.isStale ? "等待电脑同步" : context.state.headline)
                        .font(.subheadline.bold()).lineLimit(1).contentTransition(.numericText())
                }
                DynamicIslandExpandedRegion(.bottom) { TaskRows(context: context).padding(.top, 4) }
            } compactLeading: {
                HStack(spacing: 4) {
                    BrandLogo(size: 22)
                    if let count = context.state.totalTasks, count > 1 {
                        Text("\(count)").font(.caption2.bold()).foregroundStyle(orange).contentTransition(.numericText())
                    }
                }
            } compactTrailing: {
                RunningSignal(state: context.state, stale: context.isStale).frame(maxWidth: 58)
            } minimal: {
                ZStack(alignment: .bottomTrailing) {
                    BrandLogo(size: 22)
                    Circle().fill(context.state.needsApproval ? .red : orange).frame(width: 6, height: 6)
                }.accessibilityLabel(context.state.headline)
            }
            .widgetURL(overviewURL(context.attributes))
            .keylineTint(orange)
        }
    }
}

/// ActivityKit owns timer refresh and update animations; no repeatForever or artificial progress.
private struct RunningSignal: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: SessionActivityAttributes.ContentState
    let stale: Bool
    var body: some View {
        Group {
            if stale {
                Image(systemName: "wifi.exclamationmark").accessibilityLabel("等待同步")
            } else if state.needsApproval {
                Label("\(max(1, state.pendingApprovals))", systemImage: "exclamationmark.shield.fill")
                    .contentTransition(.numericText())
            } else if let start = state.startedAt, state.isRunning {
                Text(start, style: .timer).monospacedDigit().contentTransition(.numericText(countsDown: false))
                    .accessibilityLabel("任务运行时间")
            } else {
                Image(systemName: state.isRunning ? "waveform" : "checkmark.circle.fill")
                    .symbolEffect(.pulse, options: .nonRepeating, value: reduceMotion ? nil : state.updatedAt)
            }
        }
        .font(.caption2.bold()).foregroundStyle(state.needsApproval ? .red : orange)
        .lineLimit(1).minimumScaleFactor(0.7)
    }
}

private struct TaskRows: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let context: ActivityViewContext<SessionActivityAttributes>
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let tasks = context.state.tasks {
                ForEach(tasks.prefix(3)) { task in
                    Link(destination: sessionURL(task.id, context.attributes)) {
                        HStack(spacing: 8) {
                            Image(systemName: task.status == "waiting_approval" ? "exclamationmark.shield.fill" : "waveform")
                                .foregroundStyle(task.status == "waiting_approval" ? .red : orange).frame(width: 18)
                                .symbolEffect(.pulse, options: .nonRepeating, value: reduceMotion ? nil : context.state.updatedAt)
                            Text(task.title).font(.caption.weight(.medium)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(task.status == "waiting_approval" ? "待批准" : task.agent)
                                .font(.caption2).foregroundStyle(.secondary)
                        }.frame(minHeight: 25).contentShape(Rectangle())
                    }.tint(.white)
                }
                let remaining = max(0, (context.state.totalTasks ?? tasks.count) - 3)
                if remaining > 0 {
                    Text("还有 \(remaining) 个 · 轻点查看全部").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text(context.attributes.title).font(.subheadline).lineLimit(1)
                Text(context.state.headline).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

private func overviewURL(_ attributes: SessionActivityAttributes) -> URL {
    var c = URLComponents(); c.scheme = "yzvibe"; c.host = "tasks"
    c.queryItems = [URLQueryItem(name: "device", value: attributes.sessionId.hasPrefix("overview:") ? String(attributes.sessionId.dropFirst(9)) : nil)]
    return c.url!
}
private func sessionURL(_ id: String, _ attributes: SessionActivityAttributes) -> URL {
    var c = URLComponents(url: overviewURL(attributes), resolvingAgainstBaseURL: false)!
    c.host = "session"; c.queryItems?.append(URLQueryItem(name: "id", value: id)); return c.url!
}
