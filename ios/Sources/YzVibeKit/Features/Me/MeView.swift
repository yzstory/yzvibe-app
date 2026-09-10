import SwiftUI

struct MeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @AppStorage("yz.appearance") private var appearanceRaw = Settings.Appearance.auto.rawValue

    private var pushReady: Bool { store.push?.ready == true && PushCenter.shared.token != nil }
    private var ruleCount: Int { store.rules(for: store.selectedDevice?.id).count }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            PageScaffold(eyebrow: "YzVibe", title: "我") {
                HStack(spacing: 14) {
                    Image(systemName: "iphone").font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LinearGradient(colors: [p.brand, p.amber], startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .shadow(color: p.brand.opacity(0.3), radius: 10, y: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("这台 iPhone").font(.yzHeadline).foregroundStyle(p.label)
                        Text("\(store.devices.count) 台已配对电脑 · 无账号，本地优先").font(.yzFootnote).foregroundStyle(p.labelSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.labelTertiary)
                }
                .padding(Spacing.card)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                SectionCard("通知") {
                    NavigationLink { PushSettingsView() } label: {
                        SettingRow(icon: "bell.badge", color: p.danger, title: "远程推送",
                                   subtitle: pushReady ? "锁屏也能收到审批" : "没开通，锁屏后收不到审批") {
                            HStack(spacing: 6) {
                                Circle().fill(pushReady ? p.sage : p.amber).frame(width: 8, height: 8)
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.labelTertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Divider_()
                    SettingRow(icon: "bell", color: p.danger, title: "有待审批时通知") { Toggle("", isOn: $store.settings.notifyOnApproval).labelsHidden().tint(p.brand) }
                    Divider_()
                    SettingRow(icon: "bubble.left", color: p.sage, title: "回复完成时通知") { Toggle("", isOn: $store.settings.notifyOnReply).labelsHidden().tint(p.brand) }
                }
                SectionCard("会话列表") {
                    SettingRow(icon: "folder", color: p.amberText, title: "按文件夹分组") { Toggle("", isOn: $store.settings.groupByFolder).labelsHidden().tint(p.brand) }
                    Divider_()
                    SettingRow(icon: "bolt", color: p.brand, title: "仅显示活跃") { Toggle("", isOn: $store.settings.activeOnly).labelsHidden().tint(p.brand) }
                    Divider_()
                    SettingRow(icon: "terminal", color: p.sage, title: "显示终端里的会话", subtitle: "电脑上用 claude / codex 跑过的会话也能接着聊") { Toggle("", isOn: $store.settings.showTerminalSessions).labelsHidden().tint(p.brand) }
                }
                SectionCard("Agent") {
                    NavigationLink { ModelListEditorView() } label: {
                        SettingRow(icon: "cpu", color: p.purple, title: "模型列表", subtitle: "会话里可选的模型 ID 与版本") { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.labelTertiary) }
                    }
                    .buttonStyle(.plain)
                }
                SectionCard("外观") {
                    SegmentedPills(items: [(Settings.Appearance.auto, "自动"), (.light, "浅色"), (.dark, "深色")],
                                   selection: Binding(get: { Settings.Appearance(rawValue: appearanceRaw) ?? .auto }, set: { appearanceRaw = $0.rawValue }))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                }
                SectionCard("安全") {
                    NavigationLink { RulesView() } label: {
                        SettingRow(icon: "checkmark.shield", color: p.sage, title: "审批规则",
                                   subtitle: ruleCount == 0 ? "没有自动放行的规则" : "\(ruleCount) 条自动放行，可随时撤销") {
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.labelTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    Divider_()
                    SettingRow(icon: "faceid", color: p.purple, title: "高风险审批需 Face ID") { Toggle("", isOn: $store.settings.faceIDForHighRisk).labelsHidden().tint(p.brand) }
                    Divider_()
                    SettingRow(icon: "lock", color: p.blue, title: "Token 存储") { Text("钥匙串").font(.yzFootnote).foregroundStyle(p.labelSecondary) }
                }
                SectionCard("关于") {
                    SettingRow(icon: "info", color: p.labelTertiary, title: "版本") { Text("0.1.0 (1)").font(.yzMono).foregroundStyle(p.labelSecondary) }
                    Divider_()
                    SettingRow(icon: "doc.text", color: p.labelTertiary, title: "隐私与本地优先", subtitle: "数据留在你的电脑，手机不运行任何代码") { EmptyView() }
                }
            }
        }
    }
}
