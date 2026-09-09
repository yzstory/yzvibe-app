import SwiftUI

struct DevicesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @State private var showScanner = false
    @State private var showManual = false
    var onOpenSessions: () -> Void

    var body: some View {
        NavigationStack {
            PageScaffold(eyebrow: "YzVibe", title: "设备", subtitle: "已配对的电脑保存在本机，离开桌面也能一键重连。") {
                if store.devices.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 14) {
                        ForEach(store.devices) { device in
                            Button {
                                store.selectedDeviceId = device.id
                                onOpenSessions()
                            } label: { DeviceCard(device: device) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("刷新") { Task { await store.refresh(device) } }
                                Button("移除设备", role: .destructive) { store.remove(device) }
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                GlassGroup {
                    HStack(spacing: 10) {
                        Button { showScanner = true } label: { Label("扫码配对", systemImage: "qrcode.viewfinder") }
                            .buttonStyle(.yzPrimary)
                            .frame(maxWidth: .infinity)
                        Button { showManual = true } label: { Label("手动添加", systemImage: "pencil") }
                            .buttonStyle(.yzGlass)
                            .frame(width: 150)
                    }
                }
                .padding(.horizontal, Spacing.page)
                .padding(.bottom, 8)
            }
            .fullScreenCover(isPresented: $showScanner) { PairScannerView() }
            .sheet(isPresented: $showManual) { ManualEndpointView().presentationDetents([.medium, .large]) }
        }
    }

    private var emptyState: some View {
        PaperCard {
            VStack(spacing: 14) {
                Image(systemName: "qrcode.viewfinder").font(.system(size: 44, weight: .light)).foregroundStyle(p.brand)
                Text("还没有配对的电脑").font(.yzHeadline).foregroundStyle(p.label)
                Text("在电脑上运行下面命令，然后扫描终端里的二维码。").font(.yzSubhead).foregroundStyle(p.labelSecondary).multilineTextAlignment(.center)
                CodeBlock("npx yzvibe")
                Button("先看看演示数据") { store.loadDemo() }.font(.yzSubhead).foregroundStyle(p.brand)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct DeviceCard: View {
    @Environment(\.palette) private var p
    let device: Device

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 20))
                        .foregroundStyle(p.labelSecondary)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(p.fill))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            StatusDot(device.online ? .sage : .off)
                            Text(device.name).font(.yzTitle2).foregroundStyle(p.label).lineLimit(1)
                        }
                        Text(device.endpoint).font(.yzMono).foregroundStyle(p.labelSecondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(p.labelTertiary)
                }
                HStack(spacing: 8) {
                    Chip.mode(device.mode)
                    if device.online { Chip("在线", tone: .sage) } else { Chip("离线 · \(RelativeTime.string(from: device.lastSeen))", tone: .fill) }
                    ForEach(device.agents.sorted { $0.key.rawValue < $1.key.rawValue }, id: \.key) { kind, n in
                        Chip.agent(kind, suffix: "\(n)")
                    }
                    Spacer(minLength: 0)
                    Text("\(device.sessionCount) 个会话").font(.yzFootnote).foregroundStyle(p.labelSecondary)
                }
            }
        }
    }
}

/// 手动添加端点：Host / Port / Token。
struct ManualEndpointView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var port = String(Device.defaultPort)
    @State private var token = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        PaperCard {
                            VStack(alignment: .leading, spacing: 16) {
                                Eyebrow("连接到你的连接器")
                                Text("支持局域网 IP、Tailscale IP，或 https:// 开头的 relay 地址。").font(.yzFootnote).foregroundStyle(p.labelSecondary)
                                HStack(spacing: 10) {
                                    field("Host", text: $host, placeholder: "192.168.0.11")
                                    field("Port", text: $port, placeholder: String(Device.defaultPort)).frame(width: 110).keyboardType(.numberPad)
                                }
                                field("Token", text: $token, placeholder: "终端里显示的配对 Token", secure: true)
                                if let error { Text(error).font(.yzFootnote).foregroundStyle(p.danger) }
                            }
                        }
                        Button {
                            Task { await connect() }
                        } label: {
                            if busy { ProgressView().tint(p.brandInk) } else { Label("连接", systemImage: "arrow.right") }
                        }
                        .buttonStyle(.yzPrimary)
                        .disabled(host.isEmpty || token.isEmpty || busy)
                    }
                    .padding(Spacing.page)
                }
            }
            .navigationTitle("手动添加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.yzSubhead).fontWeight(.semibold).foregroundStyle(p.label)
            Group {
                if secure { SecureField(placeholder, text: text) } else { TextField(placeholder, text: text) }
            }
            .font(.yzMonoBody)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(p.fill).overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(p.border, lineWidth: 1)))
        }
    }

    private func connect() async {
        busy = true; error = nil
        do {
            try await store.addManual(host: host.trimmingCharacters(in: .whitespaces), port: Int(port) ?? Device.defaultPort, token: token)
            dismiss()
        } catch let e {
            error = e.localizedDescription
        }
        busy = false
    }
}
