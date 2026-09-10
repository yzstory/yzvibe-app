import SwiftUI

/// 审批规则：审批卡上点过「总是允许」的都在这里，可以逐条撤销。
/// 规则存在连接器上（~/.yzvibe/rules.json），换手机也还在。
struct RulesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @State private var loading = false

    private var device: Device? { store.selectedDevice }
    private var rules: [ApprovalRule] { store.rules(for: device?.id) }

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("这些规则会让同类请求不再发到手机上。删掉之后，下次又会正常询问。")
                        .font(.yzSubhead).foregroundStyle(p.labelSecondary)
                    if rules.isEmpty {
                        PaperCard {
                            VStack(spacing: 10) {
                                Image(systemName: "checkmark.shield").font(.system(size: 34, weight: .light)).foregroundStyle(p.sage)
                                Text(loading ? "正在读取…" : "还没有规则").font(.yzHeadline).foregroundStyle(p.label)
                                Text("在审批卡上点「总是允许…」就会在这里出现。").font(.yzSubhead).foregroundStyle(p.labelSecondary).multilineTextAlignment(.center)
                            }.frame(maxWidth: .infinity)
                        }
                    } else {
                        ForEach(rules) { rule in
                            PaperCard(padding: 16) {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 8) {
                                        Chip(rule.scope == "global" ? "所有会话" : "本会话", tone: rule.scope == "global" ? .custom : .brand)
                                        if let t = rule.tool { Chip(t, tone: .fill, mono: true) }
                                        Spacer(minLength: 4)
                                        if let r = rule.remaining { Text(r).font(.yzFootnote).foregroundStyle(p.labelTertiary) }
                                    }
                                    Text(rule.description).font(.yzBody).foregroundStyle(p.label)
                                    HStack {
                                        Text(rule.hits > 0 ? "已自动放行 \(rule.hits) 次" : "还没用到过").font(.yzFootnote).foregroundStyle(p.labelSecondary)
                                        Spacer()
                                        Button(role: .destructive) {
                                            Task { if let d = device { await store.deleteRule(rule, on: d.id) } }
                                        } label: {
                                            Label("撤销", systemImage: "trash").font(.system(size: 14, weight: .semibold))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(Spacing.page)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("审批规则")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let d = device else { return }
        loading = true
        await store.loadRules(for: d)
        loading = false
    }
}

/// 远程推送的状态与配置指引。没有它，App 被系统挂起后就收不到审批。
struct PushSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p

    private var status: PushStatus? { store.push }
    private var deviceName: String { store.selectedDevice?.name ?? "这台电脑" }

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PaperCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(ready ? p.sage : p.amberText)
                                Text(ready ? "推送已打通" : "推送还没打通").font(.yzTitle2).foregroundStyle(p.label)
                            }
                            Text(ready
                                 ? "App 被系统挂起时，\(deviceName) 会把待审批直接推到锁屏上。"
                                 : "现在只有 App 在前台时才能收到审批。锁屏或切走之后，请求会在电脑上一直等到超时。")
                                .font(.yzSubhead).foregroundStyle(p.labelSecondary)
                            row("手机通知权限", PushCenter.shared.authorized ? "已开启" : "未开启")
                            row("APNs token", PushCenter.shared.token == nil ? "未获取" : "已获取（\(PushCenter.shared.environment)）")
                            row("电脑端推送密钥", status?.ready == true ? "已配置" : (status?.missing ?? "未知"))
                            if let e = PushCenter.shared.lastError { row("上次错误", e) }
                        }
                    }
                    if !ready {
                        PaperCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Eyebrow("怎么打开")
                                stepText("1", "在苹果开发者后台建一个 APNs 密钥，下载 AuthKey_XXXXXXXXXX.p8")
                                stepText("2", "把 .p8 放进电脑的 ~/.yzvibe/ 目录")
                                stepText("3", "写 ~/.yzvibe/apns.json，填上你的 Team ID：")
                                CodeBlock("{ \"teamId\": \"你的 TeamID\",\n  \"bundleId\": \"\(Bundle.main.bundleIdentifier ?? "icu.yzvibe.YzVibe")\",\n  \"environment\": \"\(PushCenter.shared.environment)\" }", dark: true, lines: nil)
                                stepText("4", "电脑上运行 yzvibe restart，再回到这里下拉刷新")
                                Text("检查是否成功：电脑上运行 yzvibe push --test").font(.yzFootnote).foregroundStyle(p.labelTertiary)
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        Button {
                            Task { await PushCenter.shared.start(); if let t = PushCenter.shared.token { await store.registerPush(token: t, environment: PushCenter.shared.environment) }; await store.resync() }
                        } label: { Label("重新注册", systemImage: "arrow.clockwise") }
                            .buttonStyle(.yzSecondary)
                        if store.pushToken != nil {
                            Button { Task { await store.disablePush(); await store.resync() } } label: { Text("停用推送") }
                                .buttonStyle(OutlineButtonStyle(color: p.danger, height: 50))
                        }
                    }
                }
                .padding(Spacing.page)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("远程推送")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.resync() }
    }

    private var ready: Bool { status?.ready == true && PushCenter.shared.token != nil && PushCenter.shared.authorized }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.yzSubhead).foregroundStyle(p.labelSecondary)
            Spacer(minLength: 12)
            Text(v).font(.yzSubhead).foregroundStyle(p.label).multilineTextAlignment(.trailing)
        }
    }

    private func stepText(_ n: String, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(n).font(.yzCaption).fontWeight(.bold).foregroundStyle(p.brandInk)
                .frame(width: 18, height: 18).background(Circle().fill(p.brand))
            Text(t).font(.yzSubhead).foregroundStyle(p.label)
        }
    }
}
