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
            List {
                Section { header }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

                Section("通知") {
                    NavigationLink {
                        PushSettingsView()
                    } label: {
                        SettingRow(icon: "bell.badge", color: p.danger, title: "远程推送",
                                   subtitle: pushReady ? "锁屏也能收到审批" : "没开通，锁屏后收不到审批", inset: 0) {
                            Circle().fill(pushReady ? p.sage : p.amber).frame(width: 8, height: 8)
                        }
                    }
                    SettingRow(icon: "bell", color: p.danger, title: "有待审批时通知", inset: 0) {
                        Toggle("", isOn: $store.settings.notifyOnApproval).labelsHidden()
                    }
                    SettingRow(icon: "bubble.left", color: p.sage, title: "回复完成时通知", inset: 0) {
                        Toggle("", isOn: $store.settings.notifyOnReply).labelsHidden()
                    }
                    SettingRow(icon: "capsule.portrait", color: p.amber, title: "锁屏 / 灵动岛",
                               subtitle: "会话在跑什么、要不要你批，抬手就能看到", inset: 0) {
                        Toggle("", isOn: $store.settings.liveActivity).labelsHidden()
                    }
                }

                Section("会话列表") {
                    SettingRow(icon: "folder", color: p.amber, title: "按文件夹分组", inset: 0) {
                        Toggle("", isOn: $store.settings.groupByFolder).labelsHidden()
                    }
                    SettingRow(icon: "bolt", color: p.brand, title: "仅显示活跃", inset: 0) {
                        Toggle("", isOn: $store.settings.activeOnly).labelsHidden()
                    }
                    SettingRow(icon: "terminal", color: p.sage, title: "显示终端里的会话",
                               subtitle: "电脑上用 claude / codex 跑过的会话也能接着聊", inset: 0) {
                        Toggle("", isOn: $store.settings.showTerminalSessions).labelsHidden()
                    }
                }

                Section("Agent") {
                    NavigationLink {
                        ModelListEditorView()
                    } label: {
                        SettingRow(icon: "cpu", color: p.purple, title: "模型列表",
                                   subtitle: "会话里可选的模型 ID 与版本", inset: 0) { EmptyView() }
                    }
                }

                Section("外观") {
                    Picker("外观", selection: $appearanceRaw) {
                        Text("自动").tag(Settings.Appearance.auto.rawValue)
                        Text("浅色").tag(Settings.Appearance.light.rawValue)
                        Text("深色").tag(Settings.Appearance.dark.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }

                Section("安全") {
                    NavigationLink {
                        RulesView()
                    } label: {
                        SettingRow(icon: "checkmark.shield", color: p.sage, title: "审批规则",
                                   subtitle: ruleCount == 0 ? "没有自动放行的规则" : "\(ruleCount) 条自动放行，可随时撤销", inset: 0) { EmptyView() }
                    }
                    SettingRow(icon: "faceid", color: p.purple, title: "高风险审批需 Face ID", inset: 0) {
                        Toggle("", isOn: $store.settings.faceIDForHighRisk).labelsHidden()
                    }
                    SettingRow(icon: "lock", color: p.blue, title: "Token 存储", inset: 0) {
                        Text("钥匙串").font(.yzSubhead).foregroundStyle(p.labelSecondary)
                    }
                }

                Section {
                    SettingRow(icon: "info", color: p.labelTertiary, title: "版本", inset: 0) {
                        Text("0.1.0 (1)").font(.yzMono).foregroundStyle(p.labelSecondary)
                    }
                    SettingRow(icon: "doc.text", color: p.labelTertiary, title: "隐私与本地优先",
                               subtitle: "数据留在你的电脑，手机不运行任何代码", inset: 0) { EmptyView() }
                } header: {
                    Text("关于")
                } footer: {
                    Text("YzVibe 不需要账号，会话记录保存在你的电脑上。")
                }
            }
            .listStyle(.insetGrouped)
            .paperBackground()
            .navigationTitle("我")
        }
    }

    /// 顶部身份卡：唯一一处品牌渐变，其余全交给系统列表。
    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "iphone")
                .font(.system(.title2, weight: .semibold))
                .foregroundStyle(p.brandInk)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [p.brand, p.amber], startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("这台 iPhone").font(.yzHeadline).foregroundStyle(p.label)
                Text("\(store.devices.count) 台已配对电脑 · 无账号，本地优先")
                    .font(.yzFootnote).foregroundStyle(p.labelSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
