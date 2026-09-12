import SwiftUI
import UIKit

struct DevicesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @State private var showScanner = false
    @State private var showManual = false
    @State private var editingDevice: Device?
    @State private var diagnosingDevice: Device?
    var onOpenSessions: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if store.devices.isEmpty {
                    emptyState
                        .listRowInsets(EdgeInsets(top: 8, leading: Spacing.page, bottom: 8, trailing: Spacing.page))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(store.devices) { device in
                            VStack(alignment: .trailing, spacing: 4) {
                                Button {
                                    store.selectedDeviceId = device.id
                                    onOpenSessions()
                                } label: { DeviceCard(device: device) }
                                HStack(spacing: 12) {
                                Button { diagnosingDevice = device } label: {
                                    Label("诊断", systemImage: "stethoscope").font(.yzFootnoteStrong).foregroundStyle(p.brand).frame(minHeight: 44)
                                }
                                Button { editingDevice = device } label: {
                                    Label("配置", systemImage: "slider.horizontal.3")
                                        .font(.yzFootnoteStrong).foregroundStyle(p.brand)
                                        .padding(.horizontal, 12).frame(minHeight: 44)
                                }
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 6, leading: Spacing.page, bottom: 6, trailing: Spacing.page))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { store.remove(device) } label: { Label("移除", systemImage: "trash") }
                                Button { Task { await store.refresh(device) } } label: { Label("刷新", systemImage: "arrow.clockwise") }
                                    .tint(p.labelSecondary)
                            }
                            .contextMenu {
                                Button { editingDevice = device } label: { Label("编辑配置", systemImage: "slider.horizontal.3") }
                                Button { Task { await store.refresh(device) } } label: { Label("刷新", systemImage: "arrow.clockwise") }
                                Button { Task { await store.reconnectViaLAN(device, quiet: false) } } label: { Label("在局域网里找", systemImage: "wifi") }
                                Button(role: .destructive) { store.remove(device) } label: { Label("移除设备", systemImage: "trash") }
                            }
                            // 隧道地址变了就连不上；同一个 Wi-Fi 下不用重扫码，找一下就行
                            if !device.online {
                                Button { Task { await store.reconnectViaLAN(device, quiet: false) } } label: {
                                    Label("连不上？在同一 Wi-Fi 下找回这台电脑", systemImage: "wifi")
                                        .font(.yzFootnoteStrong).foregroundStyle(p.brand)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 0, leading: Spacing.page + 14, bottom: 10, trailing: Spacing.page))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        }
                    } footer: {
                        Text("已配对的电脑保存在本机，离开桌面也能一键重连。")
                            .font(.yzFootnote)
                            .padding(.horizontal, Spacing.page).padding(.top, 6)
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
            .paperBackground()
            .navigationTitle("设备")
            .refreshable { for d in store.devices { await store.refresh(d) } }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Button { showScanner = true } label: { Label("扫码配对", systemImage: "qrcode.viewfinder") }
                        .buttonStyle(.yzPrimary)
                    Button { showManual = true } label: { Label("手动添加", systemImage: "pencil") }
                        .buttonStyle(.yzSecondary)
                        .frame(width: 148)
                }
                .padding(.horizontal, Spacing.page)
                .padding(.bottom, 8)
            }
            .fullScreenCover(isPresented: $showScanner) { PairScannerView() }
            .sheet(isPresented: $showManual) { ManualEndpointView().presentationDetents([.medium, .large]) }
            .sheet(item: $editingDevice) { DeviceConfigurationView(device: $0) }
            .sheet(item: $diagnosingDevice) { device in NavigationStack { ConnectionDiagnosticsView(device: device) } }
        }
    }

    private var emptyState: some View {
        PaperCard {
            VStack(spacing: 12) {
                Image(systemName: "qrcode.viewfinder").font(.system(size: 42, weight: .light)).foregroundStyle(p.brand)
                Text("还没有配对的电脑").font(.yzHeadline).foregroundStyle(p.label)
                Text("在电脑上运行下面命令，然后扫描终端里的二维码。")
                    .font(.yzSubhead).foregroundStyle(p.labelSecondary).multilineTextAlignment(.center)
                CodeBlock("npx yzvibe")
                Button("先看看演示数据") { store.loadDemo() }.font(.yzSubhead).foregroundStyle(p.brand)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}

struct DeviceCard: View {
    @Environment(\.palette) private var p
    let device: Device

    var body: some View {
        PaperCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(.title3))
                        .foregroundStyle(p.labelSecondary)
                        .frame(width: 42, height: 42)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(p.fill))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            StatusDot(device.online ? .sage : .off)
                            Text(device.name).font(.yzTitle3).foregroundStyle(p.label).lineLimit(1)
                        }
                        Text(device.endpoint).font(.yzMono).foregroundStyle(p.labelSecondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.system(.footnote, weight: .semibold)).foregroundStyle(p.labelTertiary)
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

/// 手动添加端点：粘贴 `yzvibe qr --json` 的配置 / 外链 / 深链，或自己填 Host / Port / Token。
struct ManualEndpointView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var port = String(Device.defaultPort)
    @State private var token = ""
    @State private var pasted = ""
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $pasted)
                        .font(.yzMono)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .scrollContentBackground(.hidden)
                        .frame(height: 96)
                        .overlay(alignment: .topLeading) {
                            if pasted.isEmpty {
                                Text("{ \"yzvibe\": 1, \"host\": …, \"token\": … }")
                                    .font(.yzMono).foregroundStyle(p.labelTertiary)
                                    .padding(.top, 8).allowsHitTesting(false)
                            }
                        }
                    HStack(spacing: 16) {
                        Button { pasteFromClipboard() } label: { Label("从剪贴板粘贴", systemImage: "doc.on.clipboard") }
                        Spacer(minLength: 0)
                        Button { applyPasted() } label: { Label("填入", systemImage: "wand.and.stars") }
                            .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .buttonStyle(.borderless)
                    .font(.yzSubhead)
                } header: {
                    Text("粘贴配置")
                } footer: {
                    if let notice { Text(notice).foregroundStyle(p.sage) }
                    else { Text("在电脑上运行 yzvibe qr，把 JSON 配置或链接粘到这里，字段会自动填好。") }
                }

                Section {
                    LabeledContent("Host") {
                        TextField("192.168.0.11", text: $host)
                            .font(.yzMonoBody).multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    LabeledContent("Port") {
                        TextField(String(Device.defaultPort), text: $port)
                            .font(.yzMonoBody).multilineTextAlignment(.trailing).keyboardType(.numberPad)
                    }
                    LabeledContent("Token") {
                        SecureField("终端里显示的配对 Token", text: $token)
                            .font(.yzMonoBody).multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                } header: {
                    Text("或者手填")
                } footer: {
                    if let error { Text(error).foregroundStyle(p.danger) }
                    else { Text("支持局域网 IP、Tailscale IP，或 https:// 开头的 relay 地址。") }
                }
            }
            .paperBackground()
            .navigationTitle("手动添加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button { Task { await connect() } } label: {
                    if busy { ProgressView().tint(p.brandInk) } else { Label("连接", systemImage: "arrow.right") }
                }
                .buttonStyle(.yzPrimary)
                .disabled(host.isEmpty || token.isEmpty || busy)
                .padding(.horizontal, Spacing.page).padding(.bottom, 8)
            }
        }
    }

    private func pasteFromClipboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { error = "剪贴板里没有文字"; return }
        pasted = text
        applyPasted()
    }

    /// 解析粘贴的内容；成功就填好三个字段（不自动连接，让用户核对一眼）。
    private func applyPasted() {
        error = nil; notice = nil
        guard let payload = PairingPayload(text: pasted) else {
            error = "没认出这段内容，请粘贴 yzvibe qr 输出的 JSON 或链接"; return
        }
        host = payload.host
        port = String(payload.port)
        token = payload.token
        notice = "已填入\(payload.name.map { "：" + $0 } ?? "")，点「连接」即可"
    }

    private func connect() async {
        busy = true; error = nil; notice = nil
        do {
            // 粘贴过配置就沿用它带的 mode / name，否则按 host 形态猜
            let pastedPayload = PairingPayload(text: pasted)
            let h = host.trimmingCharacters(in: .whitespaces)
            let pt = Int(port) ?? Device.defaultPort
            if let pastedPayload, pastedPayload.host == h, pastedPayload.token == token {
                try await store.pair(pastedPayload)
            } else {
                try await store.addManual(host: h, port: pt, token: token)
            }
            dismiss()
        } catch let e {
            error = e.localizedDescription
        }
        busy = false
    }
}
