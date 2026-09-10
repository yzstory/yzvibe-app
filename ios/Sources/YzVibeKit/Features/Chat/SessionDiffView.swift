import SwiftUI

/// 会话改动：这个工作目录现在有哪些文件被改了、改了什么。
/// 聊天记录里逐条拼「它到底改了哪些东西」很累，这里一次看全。
struct SessionDiffView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    let sessionId: String

    @State private var diff: WorkingDiff?
    @State private var loading = true
    @State private var scope = "working"
    @State private var expanded: Set<String> = []

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if store.session(sessionId)?.baseCommit != nil {
                        SegmentedPills(items: [("working", "全部未提交"), ("session", "这次会话")], selection: $scope)
                    }
                    if loading && diff == nil {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    } else if let d = diff, !d.repo {
                        PaperCard {
                            VStack(spacing: 10) {
                                Image(systemName: "questionmark.folder").font(.system(size: 34, weight: .light)).foregroundStyle(p.labelTertiary)
                                Text(d.reason ?? "看不到改动对比").font(.yzSubhead).foregroundStyle(p.labelSecondary).multilineTextAlignment(.center)
                            }.frame(maxWidth: .infinity)
                        }
                    } else if let d = diff, d.files.isEmpty {
                        PaperCard {
                            VStack(spacing: 10) {
                                Image(systemName: "checkmark.seal").font(.system(size: 34, weight: .light)).foregroundStyle(p.sage)
                                Text("工作目录是干净的").font(.yzHeadline).foregroundStyle(p.label)
                                Text(scope == "session" ? "这次会话还没有改动任何文件。" : "没有未提交的改动。").font(.yzSubhead).foregroundStyle(p.labelSecondary)
                            }.frame(maxWidth: .infinity)
                        }
                    } else if let d = diff {
                        summary(d)
                        ForEach(d.files) { f in fileCard(f) }
                        if d.truncated {
                            Text("改动很多，只显示了前面一部分。").font(.yzFootnote).foregroundStyle(p.labelTertiary)
                        }
                    }
                }
                .padding(Spacing.page)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("改动")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) { Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") } }
        }
        .task(id: scope) { await load() }
    }

    private func summary(_ d: WorkingDiff) -> some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if let b = d.branch { Chip(b, tone: .brand, icon: "arrow.triangle.branch", mono: true) }
                    Spacer()
                    Text("\(d.totals.files) 个文件").font(.yzFootnote).foregroundStyle(p.labelSecondary)
                }
                HStack(spacing: 14) {
                    Label("\(d.totals.added)", systemImage: "plus").font(.yzHeadline).foregroundStyle(p.sage)
                    Label("\(d.totals.removed)", systemImage: "minus").font(.yzHeadline).foregroundStyle(p.danger)
                    Spacer()
                }
                if let h = d.head { Text("基线 \(h)").font(.yzCaption).monospaced().foregroundStyle(p.labelTertiary).lineLimit(1) }
            }
        }
    }

    private func fileCard(_ f: DiffFile) -> some View {
        let open = expanded.contains(f.path)
        return PaperCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(Motion.quick) { if open { expanded.remove(f.path) } else { expanded.insert(f.path) } }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: icon(for: f)).font(.system(size: 14, weight: .semibold)).foregroundStyle(color(for: f))
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color(for: f).opacity(0.14)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.name).font(.yzHeadline).foregroundStyle(p.label).lineLimit(1)
                            if !f.folder.isEmpty {
                                Text(f.folder).font(.yzCaption).monospaced().foregroundStyle(p.labelTertiary).lineLimit(1).truncationMode(.head)
                            }
                        }
                        Spacer(minLength: 6)
                        if let a = f.added, let r = f.removed {
                            HStack(spacing: 6) {
                                Text("+\(a)").font(.yzCaption).monospaced().foregroundStyle(p.sage)
                                Text("−\(r)").font(.yzCaption).monospaced().foregroundStyle(p.danger)
                            }
                        } else if f.binary {
                            Text("二进制").font(.yzCaption).foregroundStyle(p.labelTertiary)
                        }
                        if f.diff != nil {
                            Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                                .foregroundStyle(p.labelTertiary).rotationEffect(.degrees(open ? 0 : -90))
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(f.diff == nil)

                if open, let text = f.diff {
                    ToolOutputView(text: text, kind: .diff, maxHeight: 420)
                        .padding(.horizontal, 12).padding(.bottom, 12)
                }
            }
        }
        .contextMenu { Button("复制路径", systemImage: "doc.on.doc") { UIPasteboard.general.string = f.path } }
    }

    private func icon(for f: DiffFile) -> String {
        if f.untracked { return "plus.circle" }
        if f.status.contains("删除") { return "minus.circle" }
        return "pencil.circle"
    }
    private func color(for f: DiffFile) -> Color {
        if f.untracked { return p.sage }
        if f.status.contains("删除") { return p.danger }
        return p.amberText
    }

    private func load() async {
        loading = true
        diff = await store.diff(for: sessionId, scope: scope)
        loading = false
    }
}
