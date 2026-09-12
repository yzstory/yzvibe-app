import SwiftUI

struct TaskDeliveryHistoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let sessionId: String
    var body: some View {
        List {
            if let error = store.runErrors[sessionId] { Text(error).foregroundStyle(.secondary) }
            ForEach(store.taskRuns[sessionId] ?? []) { run in
                NavigationLink {
                    TaskExecutionDetailView(index: run)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(run.statusLabel)
                        Text(run.startedAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay {
            if store.taskRuns[sessionId]?.isEmpty == true {
                ContentUnavailableView("暂无执行记录", systemImage: "checklist", description: Text("最近 50 次任务会记录在这里，原始内容仍保留在会话中。"))
            }
        }
        .navigationTitle("最近 50 次任务")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .task { await store.loadRuns(sessionId) }
        .refreshable { await store.loadRuns(sessionId) }
    }
}

/// Fetch output only after opening one task. No automatic background history requests.
struct TaskExecutionDetailView: View {
    @Environment(AppStore.self) private var store
    let index: TaskRun
    @State private var detail: TaskRun?
    @State private var error: String?
    var body: some View {
        Group {
            if let detail { TaskDeliveryView(run: detail, session: store.session(index.sessionId)) }
            else if let error {
                ContentUnavailableView {
                    Label("暂时无法读取", systemImage: "wifi.exclamationmark")
                } description: { Text(error) } actions: {
                    Button("重试") { Task { await load() } }
                }
            } else { ProgressView("正在读取执行记录…") }
        }.task { await load() }
    }
    private func load() async {
        error = nil
        guard let session = store.session(index.sessionId), let device = store.device(session.deviceId) else {
            error = "会话或设备已不可用"; return
        }
        do { detail = try await store.client.run(device: device, sessionId: index.sessionId, id: index.id) }
        catch { self.error = "请检查连接后重试。" }
    }
}

struct TaskDeliveryView: View {
    @Environment(\.dismiss) private var dismiss
    let run: TaskRun
    let session: Session?
    @State private var file: DeliveryFile?
    private struct DeliveryFile: Identifiable { let path: String; var id: String { path } }
    var body: some View {
        List {
            Section("执行结果") {
                LabeledContent("本轮状态", value: run.statusLabel)
                LabeledContent("开始时间") { Text(run.startedAt, style: .time) }
                if let end = run.endedAt { LabeledContent("结束时间") { Text(end, style: .time) } }
                Text("依据连接器执行记录整理。命令完成不等于测试全部通过；请展开查看实际输出。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !run.summary.isEmpty {
                Section("助手摘要") { Text(run.summary).textSelection(.enabled) }
            }
            Section("工具与检查记录") {
                if run.tools.isEmpty { Text("本轮没有记录到工具调用，检查结果未验证。").foregroundStyle(.secondary) }
                ForEach(run.tools, id: \.id) { call in
                    DisclosureGroup {
                        Text(call.detail).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        if let code = call.exitCode { LabeledContent("退出码", value: String(code)) }
                        if let output = call.output, !output.isEmpty {
                            ToolOutputView(text: output, kind: call.outputKind, truncated: call.truncated)
                        } else { Text("没有可用的输出记录").font(.footnote).foregroundStyle(.secondary) }
                    } label: {
                        HStack {
                            Text(call.name)
                            Spacer()
                            Text(call.state == .error ? "失败" : call.state == .running ? "未结束" : "已完成")
                                .font(.caption).foregroundStyle(call.state == .error ? .red : .secondary)
                        }
                    }
                }
            }
            Section("关联文件") {
                if run.files.isEmpty { Text("本轮未记录文件改动工具。").foregroundStyle(.secondary) }
                ForEach(run.files, id: \.self) { path in
                    Button { file = DeliveryFile(path: path) } label: { Label(path, systemImage: "doc.text").font(.footnote) }
                }
                Text("文件列表来自工具输入；Shell 修改和工具未报告的文件可能不在这里。仓库累计差异仍可在「改动」中查看。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !run.artifacts.isEmpty {
                Section("产物") {
                    ForEach(run.artifacts, id: \.self) { path in
                        Button { file = DeliveryFile(path: path) } label: { Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "arrow.down.doc") }
                    }
                }
            }
        }
        .paperBackground().navigationTitle("执行记录").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .sheet(item: $file) { file in NavigationStack { FileViewerView(session: session, path: file.path) } }
    }
}

struct OutgoingMessageCard: View {
    @Environment(\.palette) private var p
    let item: OutgoingMessage
    let retry: () -> Void
    let restore: () -> Void
    private var title: String {
        switch item.state {
        case .pending: "等待发送"
        case .uploading: "正在上传附件"
        case .sending: "正在确认接收"
        case .uncertain: "发送结果待确认"
        case .failed: "尚未发送成功"
        }
    }
    var body: some View {
        PaperCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if item.busy { ProgressView() }
                    Text(title).font(.yzFootnoteStrong).foregroundStyle(p.amber)
                }
                if !item.text.isEmpty { Text(item.text).lineLimit(6).textSelection(.enabled) }
                if !item.images.isEmpty { Label("\(item.images.count) 个附件已保留", systemImage: "paperclip").font(.footnote) }
                if let issue = item.issue { Text(issue).font(.footnote).foregroundStyle(p.labelSecondary) }
                if !item.busy {
                    HStack(spacing: 20) {
                        Button(item.state == .uncertain ? "核对接收状态" : "重试发送", action: retry)
                        if item.state == .failed { Button("移回输入框", action: restore) }
                    }.font(.yzFootnoteStrong).buttonStyle(.borderless)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
