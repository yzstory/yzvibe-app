import SwiftUI

struct MeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @AppStorage("yz.appearance") private var appearanceRaw = Settings.Appearance.auto.rawValue

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
                    SettingRow(icon: "bell", color: p.danger, title: "有待审批时通知") { Toggle("", isOn: $store.settings.notifyOnApproval).labelsHidden().tint(p.brand) }
                    Divider_()
                    SettingRow(icon: "bubble.left", color: p.sage, title: "回复完成时通知") { Toggle("", isOn: $store.settings.notifyOnReply).labelsHidden().tint(p.brand) }
                }
                SectionCard("会话列表") {
                    SettingRow(icon: "folder", color: p.amberText, title: "按文件夹分组") { Toggle("", isOn: $store.settings.groupByFolder).labelsHidden().tint(p.brand) }
                    Divider_()
                    SettingRow(icon: "bolt", color: p.brand, title: "仅显示活跃") { Toggle("", isOn: $store.settings.activeOnly).labelsHidden().tint(p.brand) }
                }
                SectionCard("外观") {
                    SegmentedPills(items: [(Settings.Appearance.auto, "自动"), (.light, "浅色"), (.dark, "深色")],
                                   selection: Binding(get: { Settings.Appearance(rawValue: appearanceRaw) ?? .auto }, set: { appearanceRaw = $0.rawValue }))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                }
                SectionCard("安全") {
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
