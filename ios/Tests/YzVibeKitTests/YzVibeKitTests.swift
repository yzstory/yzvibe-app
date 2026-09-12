import XCTest
import UIKit
import CoreImage
@testable import YzVibeKit

final class YzVibeKitTests: XCTestCase {
    func testOKLCHBrandConvertsToWarmRed() {
        let s = OKLCH(0.64, 0.17, 40).srgb
        XCTAssertGreaterThan(s.r, s.g)
        XCTAssertGreaterThan(s.g, s.b)
        XCTAssertEqual(s.r, 0.87, accuracy: 0.05)   // oklch(0.64 0.17 40) ≈ rgb(221, 110, 76)。只验证换算本身；品牌色现在直接用 hex 定义，见 Palette。
    }

    func testOKLCHWhiteAndBlack() {
        let w = OKLCH(1, 0, 0).srgb
        XCTAssertEqual(w.r, 1, accuracy: 0.01)
        let k = OKLCH(0, 0, 0).srgb
        XCTAssertEqual(k.r, 0, accuracy: 0.01)
    }

    func testPairingPayloadParsesQR() throws {
        let p = try XCTUnwrap(PairingPayload(qrString: "yzvibe://pair?host=100.82.203.14&port=19876&token=abc123&mode=tailscale&name=Studio"))
        XCTAssertEqual(p.host, "100.82.203.14")
        XCTAssertEqual(p.port, 19876)
        XCTAssertEqual(p.token, "abc123")
        XCTAssertEqual(p.mode, .tailscale)
        XCTAssertEqual(p.name, "Studio")
    }

    func testPairingPayloadRejectsForeignQR() {
        XCTAssertNil(PairingPayload(qrString: "https://example.com"))
        XCTAssertNil(PairingPayload(qrString: "yzvibe://pair?host=&token=x"))
        XCTAssertNil(PairingPayload(text: "  "))
        XCTAssertNil(PairingPayload(text: "{\"hello\":1}"))
        XCTAssertNil(PairingPayload(text: "https://example.com/other?token=x"))   // 路径不是 /pair
    }

    func testPairingPayloadParsesJSONConfig() throws {
        let json = #"""
        {
          "yzvibe": 1,
          "name": "YuKisMacServer.local",
          "host": "https://abc-def.trycloudflare.com",
          "port": null,
          "token": "-FqSCst-R1itUJck",
          "mode": "tunnel",
          "connectorId": "865356ad",
          "url": "yzvibe://pair?host=x&token=y",
          "link": "https://abc-def.trycloudflare.com/pair?token=-FqSCst-R1itUJck"
        }
        """#
        let p = try XCTUnwrap(PairingPayload(text: json))
        XCTAssertEqual(p.host, "https://abc-def.trycloudflare.com")
        XCTAssertEqual(p.token, "-FqSCst-R1itUJck")
        XCTAssertEqual(p.mode, .tunnel)              // port 为 null 时回落到默认端口
        XCTAssertEqual(p.port, Device.defaultPort)
        XCTAssertEqual(p.name, "YuKisMacServer.local")
    }

    func testPairingPayloadParsesJSONWithLocalHostAndPort() throws {
        let p = try XCTUnwrap(PairingPayload(text: #"{"host":"192.168.31.121","port":19877,"token":"t1","mode":"local","name":"Mac"}"#))
        XCTAssertEqual(p.host, "192.168.31.121")
        XCTAssertEqual(p.port, 19877)
        XCTAssertEqual(p.mode, .local)
    }

    func testPairingPayloadParsesBrowserLink() throws {
        let https = try XCTUnwrap(PairingPayload(text: "https://abc-def.trycloudflare.com/pair?token=tok9"))
        XCTAssertEqual(https.host, "https://abc-def.trycloudflare.com")
        XCTAssertEqual(https.token, "tok9")
        XCTAssertEqual(https.mode, .relay)

        // 局域网外链拆成 host + port
        let lan = try XCTUnwrap(PairingPayload(text: "http://192.168.31.121:19876/pair?token=tok8"))
        XCTAssertEqual(lan.host, "192.168.31.121")
        XCTAssertEqual(lan.port, 19876)
        XCTAssertEqual(lan.mode, .local)

        let ts = try XCTUnwrap(PairingPayload(text: "http://100.82.203.14:19876/pair?token=tok7"))
        XCTAssertEqual(ts.mode, .tailscale)
    }

    func testPairingPayloadIgnoresSurroundingText() throws {
        let messy = "用手机扫这个：\n  yzvibe://pair?host=1.2.3.4&port=19876&token=abc&mode=local&name=Mac  \n（10 分钟内有效）"
        let p = try XCTUnwrap(PairingPayload(text: messy))
        XCTAssertEqual(p.host, "1.2.3.4")
        XCTAssertEqual(p.token, "abc")

        let withJSON = "复制下面的 JSON：\n{\"host\":\"1.2.3.4\",\"port\":19876,\"token\":\"zz\",\"mode\":\"local\"}\n粘贴到 App 里"
        XCTAssertEqual(PairingPayload(text: withJSON)?.token, "zz")
    }

    func testQRImageScannerReadsGeneratedCode() throws {
        let text = "yzvibe://pair?host=1.2.3.4&port=19876&token=fromimage&mode=local&name=Mac"
        let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        let ci = try XCTUnwrap(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let png = try XCTUnwrap(UIImage(ciImage: ci).pngData())
        XCTAssertEqual(QRImageScanner.decode(png), text)
        XCTAssertEqual(PairingPayload(text: try XCTUnwrap(QRImageScanner.decode(png)))?.token, "fromimage")
        // 一张没有二维码的纯色图
        let blank = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 60)).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 60, height: 60))
        }
        XCTAssertNil(QRImageScanner.decode(try XCTUnwrap(blank.pngData())))
    }

    func testFilePathDetectorAcceptsRealPaths() {
        let good = ["bin/yzvibe.js", "~/.yzvibe/pairing.txt", "src/server.js", "connector/src/files.js",
                    "README.md", "/Users/yuki/devops/a.swift", "docs/PRD.md", "ios/project.yml",
                    "package.json", ".gitignore", "~/.claude/settings.json"]
        for s in good { XCTAssertNotNil(FilePathDetector.path(in: s), "应识别为路径：\(s)") }
        // 结尾标点与包裹符号要剥掉
        XCTAssertEqual(FilePathDetector.path(in: "src/server.js。"), "src/server.js")
        XCTAssertEqual(FilePathDetector.path(in: "`README.md`"), "README.md")
        XCTAssertEqual(FilePathDetector.path(in: "(docs/PRD.md)"), "docs/PRD.md")
        XCTAssertEqual(FilePathDetector.path(in: "connector/src/"), "connector/src")
    }

    func testFilePathDetectorRejectsNonPaths() {
        let bad = ["npx yzvibe", "yzvibe qr", "--access=local", "19876", "claude-fable-5-1",
                   "https://example.com/a.md", "and/or", "GET /files", "*.swift", "npm test",
                   "-p", "yzvibe start --agent=mock"]
        for s in bad { XCTAssertNil(FilePathDetector.path(in: s), "不该当成路径：\(s)") }
    }

    func testMarkdownLinkifiesOnlyPathsInInlineCode() throws {
        // 行内代码里是路径 → 变成 yzfile:// 链接；是命令 → 保持原样
        let md = try XCTUnwrap(try? AttributedString(markdown: "打开 `src/server.js` 然后跑 `npm test`",
                                                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        let out = MarkdownText.linkifyPaths(md, tint: .red)
        let links = out.runs.compactMap(\.link)
        XCTAssertEqual(links.count, 1)
        let comps = try XCTUnwrap(URLComponents(url: try XCTUnwrap(links.first), resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.scheme, "yzfile")
        XCTAssertEqual(comps.queryItems?.first { $0.name == "path" }?.value, "src/server.js")
    }

    func testFileInfoDecodesConnectorPayload() throws {
        let json = #"{"name":"pairing.txt","path":"/Users/yuki/.yzvibe/pairing.txt","displayPath":"~/.yzvibe/pairing.txt","kind":"other","size":512,"modifiedAt":"2026-09-10T11:00:00.000Z","mime":"application/octet-stream","textual":true,"inCwd":false}"#
        let info = try JSONDecoder.yz.decode(FileInfo.self, from: Data(json.utf8))
        XCTAssertEqual(info.name, "pairing.txt")
        XCTAssertEqual(info.displayPath, "~/.yzvibe/pairing.txt")
        XCTAssertFalse(info.inCwd)
        XCTAssertTrue(info.textual)
        XCTAssertEqual(info.sizeText, ByteCountFormatter.string(fromByteCount: 512, countStyle: .file))
        // 字段缺失时也能解（连接器老版本）
        let lean = try JSONDecoder.yz.decode(FileInfo.self, from: Data(#"{"name":"a.ts"}"#.utf8))
        XCTAssertEqual(lean.path, "a.ts")
        XCTAssertTrue(lean.inCwd)
    }

    func testEventParsing() throws {
        let json = #"{"type":"approval.requested","sessionId":"s1","approvalId":"a9","kind":"shell","summary":"rm -rf dist","detail":"...","risk":"high"}"#
        let ev = try XCTUnwrap(ConnectorSocket.parse(Data(json.utf8)))
        guard case .approvalRequested(let a) = ev else { return XCTFail("wrong event") }
        XCTAssertEqual(a.id, "a9"); XCTAssertEqual(a.risk, .high); XCTAssertEqual(a.kind, .shell)
    }

    @MainActor
    func testStoreGroupsSessionsByFolder() {
        let store = AppStore()
        let groups = store.groupedSessions(store.sessions(for: MockData.macStudio, activeOnly: false, query: ""))
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first?.sessions.count, 1) // 最近更新的 YzVibe 目录在前
    }

    @MainActor
    func testApprovalRespondUpdatesSession() async {
        let store = AppStore()
        await store.respond("a1", .allow)
        XCTAssertEqual(store.approval("a1")?.status, .allowed)
        XCTAssertEqual(store.session("s1")?.pendingApprovals, 0)
        XCTAssertEqual(store.session("s1")?.status, .running)
    }
}

// MARK: - 会话选项（模式 / 模型 / 思考强度）

final class SessionOptionsTests: XCTestCase {
    func testSessionDecodesOptionsWithDefaults() throws {
        let old = #"{"id":"s1","agent":"claude","cwd":"~/x","title":"t","status":"idle"}"#
        let s1 = try JSONDecoder.yz.decode(Session.self, from: Data(old.utf8))
        XCTAssertEqual(s1.mode, .normal); XCTAssertNil(s1.model); XCTAssertNil(s1.effort)
        let new = #"{"id":"s2","agent":"codex","cwd":"~/x","title":"t","status":"idle","mode":"plan","model":"gpt-5.5","effort":"xhigh"}"#
        let s2 = try JSONDecoder.yz.decode(Session.self, from: Data(new.utf8))
        XCTAssertEqual(s2.mode, .plan); XCTAssertEqual(s2.model, "gpt-5.5"); XCTAssertEqual(s2.effort, "xhigh")
        // 空串等价未设置
        let blank = #"{"id":"s3","agent":"claude","cwd":"","title":"","status":"idle","model":"","effort":null}"#
        XCTAssertNil(try JSONDecoder.yz.decode(Session.self, from: Data(blank.utf8)).model)
    }

    func testNewSessionRequestEncodesModeNotYolo() throws {
        let r = NewSessionRequest(agent: .codex, cwd: "~/p", mode: .trust, model: "gpt-5.5", effort: "high")
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.yz.encode(r)) as? [String: Any])
        XCTAssertEqual(obj["mode"] as? String, "trust")
        XCTAssertEqual(obj["model"] as? String, "gpt-5.5")
        XCTAssertNil(obj["yolo"])
    }

    func testCapabilitiesDecodeAndModelSpecificEfforts() throws {
        let json = #"{"claude":{"modes":{"plan":{"flag":"--permission-mode plan","description":"d"}},"efforts":["low","max"],"models":[{"id":"opus","label":"Opus"}]},"codex":{"efforts":["low","high"],"models":[{"id":"gpt-5.5","label":"GPT-5.5","efforts":["low","medium","high","xhigh"]}],"customModel":true}}"#
        let caps = try JSONDecoder.yz.decode([String: AgentCapabilities].self, from: Data(json.utf8))
        XCTAssertEqual(caps["claude"]?.modeInfo(.plan)?.flag, "--permission-mode plan")
        XCTAssertEqual(caps["claude"]?.label(forModel: "opus"), "Opus")
        XCTAssertEqual(caps["claude"]?.label(forModel: "my-custom"), "my-custom")
        XCTAssertEqual(caps["codex"]?.efforts(for: "gpt-5.5"), ["low", "medium", "high", "xhigh"])
        XCTAssertEqual(caps["codex"]?.efforts(for: nil), ["low", "high"])
        XCTAssertEqual(AgentCapabilities.fallback(for: .codex).modes.count, 3)
    }

    func testSettingsRememberCustomModelsAndDefaults() throws {
        var s = Settings()
        s.addCustomModel("claude-opus-5", for: .claude)
        s.addCustomModel("x", for: .claude)
        s.addCustomModel("claude-opus-5", for: .claude)   // 去重并置顶
        XCTAssertEqual(s.customModels(for: .claude), ["claude-opus-5", "x"])
        XCTAssertEqual(s.customModels(for: .codex), [])
        s.remember(SessionOptions(mode: .plan, model: "opus", effort: "max"), for: .claude)
        let roundTrip = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(roundTrip.defaults(for: .claude), SessionOptions(mode: .plan, model: "opus", effort: "max"))
        XCTAssertEqual(roundTrip.defaults(for: .codex), SessionOptions())
        // 旧版本存的 JSON 没有新字段也能读
        let legacy = #"{"notifyOnApproval":true,"notifyOnReply":false,"groupByFolder":true,"activeOnly":false,"appearance":"dark","faceIDForHighRisk":true}"#
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: Data(legacy.utf8)).appearance, .dark)
    }

    @MainActor
    func testStoreSetModeUpdatesSessionOptimistically() async {
        let store = AppStore()
        await store.setMode(.trust, for: "s1")
        XCTAssertNil(store.toast, "configure 不应失败")
        XCTAssertEqual(store.session("s1")?.mode, .trust)
        await store.setModel("  opus ", for: "s1")
        XCTAssertEqual(store.session("s1")?.model, "opus")
        await store.setEffort("", for: "s1")
        XCTAssertNil(store.session("s1")?.effort)
        XCTAssertEqual(store.settings.defaults(for: .claude).mode, .trust)
    }
}

// MARK: - 用量 / 额度 / 图片压缩

final class UsageTests: XCTestCase {
    func testSessionDecodesUsageFromConnector() throws {
        let json = #"{"id":"s9","agent":"claude","cwd":"~","title":"t","status":"idle","usage":{"model":"claude-fable-5-1","turn":{"input":32,"cacheWrite":741,"cacheRead":127602,"output":1089,"thinking":35,"contextTokens":128375,"contextWindow":200000,"costUSD":0.08,"durationMs":2695},"total":{"input":100,"cacheWrite":800,"cacheRead":300000,"output":2000,"costUSD":0.5,"turns":3},"updatedAt":"2026-09-10T10:00:00.000Z"}}"#
        let s = try JSONDecoder.yz.decode(Session.self, from: Data(json.utf8))
        let u = try XCTUnwrap(s.usage)
        XCTAssertEqual(u.turn.totalInput, 128_375)
        XCTAssertEqual(u.turn.contextFraction.map { ($0 * 1000).rounded() / 1000 }, 0.642)
        XCTAssertEqual(u.total.turns, 3)
        // 没有 usage 或 usage 为 null 都能解
        let none = try JSONDecoder.yz.decode(Session.self, from: Data(#"{"id":"s0","agent":"codex","cwd":"~","title":"t","status":"idle","usage":null}"#.utf8))
        XCTAssertNil(none.usage)
    }

    func testQuotaDecodes() throws {
        let json = #"{"agent":"claude","source":"oauth","fetchedAt":"2026-09-10T10:00:00.000Z","limits":[{"id":"session","label":"当前会话（5 小时）","percent":24,"resetsAt":"2026-09-10T02:39:59.000Z"},{"id":"weekly_fable","label":"本周（Fable）","percent":45,"resetsAt":null}],"extraUsage":{"enabled":false,"usedCredits":0,"monthlyLimit":10000,"percent":0,"currency":"USD"}}"#
        let q = try JSONDecoder.yz.decode(QuotaInfo.self, from: Data(json.utf8))
        XCTAssertEqual(q.limits.map(\.id), ["session", "weekly_fable"])
        XCTAssertEqual(q.limits[1].percent, 45); XCTAssertNil(q.limits[1].resetsAt)
        XCTAssertEqual(q.extraUsage?.enabled, false)
        let err = try JSONDecoder.yz.decode(QuotaInfo.self, from: Data(#"{"agent":"claude","source":"none","limits":[],"error":"没登录"}"#.utf8))
        XCTAssertEqual(err.error, "没登录")
    }

    func testImageDownscaleLimitsLongEdge() throws {
        let fmt = UIGraphicsImageRendererFormat.default(); fmt.scale = 1   // 按像素算，不受模拟器 3x 屏幕影响
        let big = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 3000), format: fmt).image { ctx in UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 4000, height: 3000)) }
        let out = try XCTUnwrap(ImagePrep.downscale(try XCTUnwrap(big.pngData())))
        let img = try XCTUnwrap(UIImage(data: out))
        XCTAssertEqual(img.size.width, 1568, accuracy: 1); XCTAssertEqual(img.size.height, 1176, accuracy: 1)
        XCTAssertTrue(out.starts(with: [0xFF, 0xD8]))   // JPEG
        // 小图不放大
        let small = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200), format: fmt).image { _ in }
        let out2 = try XCTUnwrap(ImagePrep.downscale(try XCTUnwrap(small.pngData())))
        XCTAssertEqual(UIImage(data: out2)?.size.width, 300)
        XCTAssertNil(ImagePrep.downscale(Data([1, 2, 3])))
    }
}

// MARK: - 终端会话 / 模型列表

final class TerminalSessionTests: XCTestCase {
    func testSessionDecodesSourceAndBranch() throws {
        let json = #"{"id":"claude:abc","agent":"claude","cwd":"/x","title":"t","status":"idle","source":"terminal","branch":"main"}"#
        let s = try JSONDecoder.yz.decode(Session.self, from: Data(json.utf8))
        XCTAssertEqual(s.source, .terminal); XCTAssertEqual(s.branch, "main")
        let old = try JSONDecoder.yz.decode(Session.self, from: Data(#"{"id":"s","agent":"codex","cwd":"/x","title":"t","status":"idle"}"#.utf8))
        XCTAssertEqual(old.source, .phone); XCTAssertNil(old.branch)
    }

    @MainActor
    func testTerminalSessionsCanBeHidden() {
        let store = AppStore()
        store.settings.showTerminalSessions = true   // Settings 会持久化到 UserDefaults，先归位避免上次运行残留
        let all = store.sessions(for: MockData.macStudio, activeOnly: false, query: "")
        XCTAssertTrue(all.contains { $0.source == .terminal })
        store.settings.showTerminalSessions = false
        XCTAssertFalse(store.sessions(for: MockData.macStudio, activeOnly: false, query: "").contains { $0.source == .terminal })
        store.settings.showTerminalSessions = true
    }

    @MainActor
    func testModelPresetsOverrideCapabilities() throws {
        let store = AppStore()
        let caps = AgentCapabilities.fallback(for: .claude)
        XCTAssertEqual(store.modelOptions(for: .claude, caps: caps).map(\.id), ["claude-fable-5-1", "claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5-20251001"])
        store.settings.setModelPresets([ModelOption(id: "claude-opus-5-20260901", label: "Opus 5 (0901)")], for: .claude)
        XCTAssertEqual(store.modelOptions(for: .claude, caps: caps).map(\.label), ["Opus 5 (0901)"])
        XCTAssertEqual(store.modelOptions(for: .codex, caps: .fallback(for: .codex)).count, 4)   // 另一个 Agent 不受影响
        let round = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(store.settings))
        XCTAssertEqual(round.modelPresets(for: .claude)?.first?.id, "claude-opus-5-20260901")
        store.settings.setModelPresets(nil, for: .claude)
        XCTAssertNil(store.settings.modelPresets(for: .claude))
    }
}

// MARK: - 附件

final class AttachmentTests: XCTestCase {
    @MainActor
    func testSendImageOnlyKeepsTitleAndCachesAttachment() async {
        let store = AppStore()
        let s = Session(id: "sx", deviceId: "d1", agent: .claude, cwd: "~/x", title: "新会话")
        store.sessions.insert(s, at: 0)
        let fmt = UIGraphicsImageRendererFormat.default(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10), format: fmt).image { _ in }
        store.cacheAttachment(img, id: "up1")
        await store.send("", in: "sx", attachments: ["up1"])
        XCTAssertEqual(store.session("sx")?.title, "新会话")                 // 空文本不改标题
        XCTAssertEqual(store.messages["sx"]?.last?.attachments, ["up1"])
        XCTAssertNotNil(store.attachmentImages["up1"])
        // 没缓存的从连接器拉（Mock 返回色块图）
        await store.loadAttachment("up2", for: "s1")
        XCTAssertNotNil(store.attachmentImages["up2"])
        XCTAssertFalse(store.failedAttachments.contains("up2"))
    }
}

// MARK: - 会话 3 新增：工具输出、审批规则、推送、断线重同步

final class ToolOutputAndRulesTests: XCTestCase {
    private func decode<T: Decodable>(_ json: String, as: T.Type) throws -> T {
        try JSONDecoder.yzTest.decode(T.self, from: Data(json.utf8))
    }

    func testToolCallDecodesOutputAndTolerantDefaults() throws {
        let full = try decode(#"{"id":"t1","name":"Bash","detail":"npm test","state":"done","output":"PASS","outputKind":"text","truncated":true}"#, as: ToolCall.self)
        XCTAssertEqual(full.output, "PASS")
        XCTAssertEqual(full.outputKind, .text)
        XCTAssertTrue(full.truncated)

        // 老连接器不带这些字段，也不能崩
        let old = try decode(#"{"id":"t2","name":"Read","detail":"a.ts","state":"running"}"#, as: ToolCall.self)
        XCTAssertNil(old.output)
        XCTAssertEqual(old.outputKind, .text)
        XCTAssertFalse(old.truncated)

        // 未知的 outputKind 退回 text，未知 state 退回 running
        let weird = try decode(#"{"id":"t3","state":"zzz","outputKind":"html"}"#, as: ToolCall.self)
        XCTAssertEqual(weird.state, .running)
        XCTAssertEqual(weird.outputKind, .text)
    }

    func testApprovalDecodesSuggestionsAndToolName() throws {
        let a = try decode(#"""
        {"approvalId":"a1","sessionId":"s1","kind":"shell","summary":"npm test","detail":"npm test","risk":"medium","toolName":"Bash",
         "suggestions":[{"label":"总是允许 npm test 开头的命令","match":"prefix","value":"npm test","scope":"session","ttlMinutes":null},
                        {"label":"本会话 1 小时内不再询问 Bash","match":"tool","value":"Bash","scope":"session","ttlMinutes":60}]}
        """#, as: Approval.self)
        XCTAssertEqual(a.id, "a1")
        XCTAssertEqual(a.toolName, "Bash")
        XCTAssertEqual(a.suggestions.count, 2)
        XCTAssertEqual(a.suggestions[0].match, "prefix")
        XCTAssertNil(a.suggestions[0].ttlMinutes)
        XCTAssertEqual(a.suggestions[1].ttlMinutes, 60)
        XCTAssertNotEqual(a.suggestions[0].id, a.suggestions[1].id)

        // 没有 suggestions 的老数据
        let old = try decode(#"{"id":"a2","sessionId":"s","kind":"write","summary":"x","detail":"x","risk":"low"}"#, as: Approval.self)
        XCTAssertTrue(old.suggestions.isEmpty)
        XCTAssertNil(old.toolName)
    }

    func testApprovalRuleRemainingText() throws {
        let soon = ApprovalRule(id: "r", description: "d", expiresAt: Date().addingTimeInterval(1800))
        XCTAssertEqual(soon.remaining, "还剩 30 分钟")
        let later = ApprovalRule(id: "r", description: "d", expiresAt: Date().addingTimeInterval(7200))
        XCTAssertEqual(later.remaining, "还剩 2 小时")
        XCTAssertEqual(ApprovalRule(id: "r", description: "d", expiresAt: Date().addingTimeInterval(-60)).remaining, "已过期")
        XCTAssertNil(ApprovalRule(id: "r", description: "d").remaining)
    }

    func testSyncSnapshotDecodesAndTolerantOfMissingFields() throws {
        let snap = try decode(#"""
        {"serverTime":"2026-09-10T10:00:00Z","sessions":[{"id":"s1","agent":"claude","cwd":"/p","title":"t","status":"idle"}],
         "approvals":[],"agents":{},"rules":[{"id":"r1","match":"tool","tool":"Bash","description":"本会话内不再询问 Bash","hits":3}],
         "push":{"ready":false,"missing":"推送密钥 .p8","registeredDevices":0}}
        """#, as: SyncSnapshot.self)
        XCTAssertEqual(snap.sessions.count, 1)
        XCTAssertEqual(snap.rules.first?.hits, 3)
        XCTAssertFalse(snap.push.ready)
        XCTAssertEqual(snap.push.missing, "推送密钥 .p8")

        let empty = try decode("{}", as: SyncSnapshot.self)
        XCTAssertTrue(empty.sessions.isEmpty)
        XCTAssertFalse(empty.push.ready)
    }

    func testPushPayloadParsing() {
        let p = PushPayload(userInfo: ["aps": ["alert": "x"], "yz": ["kind": "approval", "approvalId": "a1", "sessionId": "s1", "connector": "Mac"]])
        XCTAssertEqual(p.kind, .approval)
        XCTAssertEqual(p.approvalId, "a1")
        XCTAssertEqual(p.sessionId, "s1")
        XCTAssertEqual(p.connector, "Mac")
        XCTAssertEqual(PushPayload(userInfo: [:]).kind, .unknown)
        XCTAssertEqual(PushPayload(userInfo: ["yz": ["kind": "reply", "sessionId": "s2"]]).kind, .reply)
    }

    func testMessageLocalFlagIsNotEncodedAndDefaultsFalse() throws {
        let local = Message(sessionId: "s", role: .user, text: "hi", isLocal: true)
        XCTAssertTrue(local.isLocal)
        let round = try decode(#"{"id":"m","sessionId":"s","role":"user","text":"hi"}"#, as: Message.self)
        XCTAssertFalse(round.isLocal, "服务端来的消息不该被当成本地乐观消息")
    }

    @MainActor
    func testResyncMergesServerMessagesAndDropsLocalDuplicates() async {
        let client = ResyncStubClient()
        let store = AppStore(client: client, seedMock: false)
        var device = MockData.macStudio
        device.online = true
        store.devices = [device]
        store.selectedDeviceId = device.id

        // 先打开一个会话，拿到服务端的历史
        store.sessions = [Session(id: "s1", deviceId: device.id, agent: .claude, cwd: "/p", title: "t")]
        await store.loadMessages("s1")
        XCTAssertEqual(store.messages["s1"]?.count, 1)

        // 断线期间：本地乐观发了一条，服务端那边其实已经存了自己的版本并有了回复
        await store.send("继续", in: "s1")
        XCTAssertEqual(store.messages["s1"]?.last?.isLocal, true)
        client.newMessages = [
            Message(id: "m2", sessionId: "s1", role: .user, text: "继续", createdAt: Date().addingTimeInterval(1)),
            Message(id: "m3", sessionId: "s1", role: .assistant, text: "好的", createdAt: Date().addingTimeInterval(2)),
        ]

        await store.resync()
        let texts = store.messages["s1"]?.map(\.text) ?? []
        XCTAssertEqual(texts, ["历史", "继续", "好的"], "本地乐观消息应被服务端版本取代，而不是重复一条")
        XCTAssertEqual(store.messages["s1"]?.filter(\.isLocal).count, 0)
        XCTAssertNil(client.lastAfterCursor ?? nil, "恢复时需要快照，才能更新已有消息的工具状态")
        XCTAssertTrue(client.reconnected, "回到前台要立刻重连事件通道")
        XCTAssertEqual(store.rules(for: device.id).count, 1)
        XCTAssertEqual(store.push?.ready, false)
    }

    @MainActor
    func testRespondPassesRememberRuleThrough() async {
        let client = ResyncStubClient()
        let store = AppStore(client: client, seedMock: false)
        var device = MockData.macStudio
        device.online = true
        store.devices = [device]
        store.selectedDeviceId = device.id
        store.sessions = [Session(id: "s1", deviceId: device.id, agent: .claude, cwd: "/p", title: "t")]
        store.approvals = [Approval(id: "a1", sessionId: "s1", deviceId: device.id, kind: .shell, summary: "npm test", detail: "", risk: .medium)]

        let rule = ApprovalSuggestion(label: "总是允许", match: "prefix", value: "npm test", scope: "session")
        await store.respond("a1", .allow, remember: rule)
        XCTAssertEqual(client.lastRemember?.match, "prefix")
        XCTAssertEqual(client.lastRemember?.value, "npm test")
        XCTAssertEqual(store.approval("a1")?.status, .allowed)
    }
}

/// 断线重同步用的假连接器：只实现这几个测试要用到的方法。
final class ResyncStubClient: ConnectorClient, @unchecked Sendable {
    var attachmentData = Data()
    var attachmentRequests = 0
    var newMessages: [Message] = []
    var lastAfterCursor: String??
    var lastRemember: ApprovalSuggestion?
    var reconnected = false

    func health(device: Device) async throws -> HealthInfo { HealthInfo(name: "T", version: "0", agents: []) }
    func pair(_ payload: PairingPayload) async throws -> Device { MockData.macStudio }
    func sessions(device: Device) async throws -> [Session] { [] }
    func createSession(device: Device, request: NewSessionRequest) async throws -> Session { MockData.sessions[0] }
    func messages(device: Device, sessionId: String, after cursor: String?) async throws -> [Message] {
        lastAfterCursor = cursor
        if cursor == nil { return [Message(id: "m1", sessionId: sessionId, role: .user, text: "历史")] + newMessages }
        return newMessages
    }
    func send(device: Device, sessionId: String, text: String, attachments: [String]) async throws {}
    func stop(device: Device, sessionId: String) async throws {}
    func respond(device: Device, approvalId: String, decision: ApprovalDecision, remember: ApprovalSuggestion?, answers: [String: String]?) async throws { lastRemember = remember }
    func approvals(device: Device) async throws -> [Approval] { [] }
    func capabilities(device: Device) async throws -> [String: AgentCapabilities] { [:] }
    func configure(device: Device, sessionId: String, patch: [String: String?]) async throws -> Session { MockData.sessions[0] }
    func quota(device: Device, agent: AgentKind) async throws -> QuotaInfo { QuotaInfo(agent: agent.rawValue) }
    func fileInfo(device: Device, sessionId: String, path: String) async throws -> FileInfo { throw ConnectorError.unreachable }
    func download(device: Device, sessionId: String, path: String) async throws -> Data { Data() }
    func attachment(device: Device, id: String) async throws -> Data { attachmentRequests += 1; return attachmentData }
    func listFiles(device: Device, sessionId: String, path: String) async throws -> [FileEntry] { [] }
    func preview(device: Device, sessionId: String, path: String) async throws -> String { "" }
    func upload(device: Device, data: Data, mime: String, filename: String) async throws -> String { "u1" }
    func listDirectories(device: Device, path: String?) async throws -> DirectoryListing { DirectoryListing(path: "/", parent: nil, home: "/", entries: []) }
    func makeDirectory(device: Device, parent: String, name: String) async throws -> String { parent }
    func sync(device: Device) async throws -> SyncSnapshot {
        SyncSnapshot(sessions: [Session(id: "s1", deviceId: device.id, agent: .claude, cwd: "/p", title: "t")],
                     rules: [ApprovalRule(id: "r1", tool: "Bash", description: "本会话内不再询问 Bash")],
                     push: PushStatus(ready: false, missing: "推送密钥 .p8"))
    }
    func rules(device: Device, sessionId: String?) async throws -> [ApprovalRule] { [ApprovalRule(id: "r1", description: "d")] }
    func deleteRule(device: Device, id: String) async throws {}
    func registerPush(device: Device, token: String, environment: String) async throws -> PushStatus { PushStatus(ready: true) }
    func unregisterPush(device: Device) async throws {}
    func reconnect(device: Device) { reconnected = true }
    func sendMessage(device: Device, sessionId: String, text: String, attachments: [String], mode: SendMode) async throws -> (queued: Bool, item: QueuedMessage?) { (false, nil) }
    func cancelQueued(device: Device, sessionId: String, itemId: String) async throws {}
    func diff(device: Device, sessionId: String, scope: String) async throws -> WorkingDiff { WorkingDiff() }
    func commands(device: Device, sessionId: String) async throws -> CommandCatalog { CommandCatalog() }
    func registerLiveActivity(device: Device, sessionId: String, token: String) async throws {}
    func events(device: Device) -> AsyncStream<ConnectorEvent> { AsyncStream { $0.finish() } }
}

extension JSONDecoder {
    static let yzTest: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}

// MARK: - 会话 3 追加：队列、地址故障转移、改动视图、命令面板、实时活动

final class QueueEndpointsAndCommandsTests: XCTestCase {
    private func decode<T: Decodable>(_ json: String, as: T.Type) throws -> T {
        try JSONDecoder.yzTest.decode(T.self, from: Data(json.utf8))
    }

    func testSessionDecodesQueueAndBaseCommit() throws {
        let s = try decode(#"""
        {"id":"s1","agent":"claude","cwd":"/p","title":"t","status":"running","baseCommit":"abc123",
         "queue":[{"id":"q1","text":"接着改","attachments":[],"createdAt":"2026-09-10T10:00:00Z"},
                  {"id":"q2","text":"再看一下测试","attachments":["u1"]}]}
        """#, as: Session.self)
        XCTAssertEqual(s.queue.count, 2)
        XCTAssertEqual(s.queue[0].text, "接着改")
        XCTAssertEqual(s.queue[1].attachments, ["u1"])
        XCTAssertEqual(s.baseCommit, "abc123")
        XCTAssertTrue(try decode(#"{"id":"s2"}"#, as: Session.self).queue.isEmpty)
    }

    func testDeviceAdoptsNewEndpoint() {
        var d = Device(name: "Mac", host: "https://old.trycloudflare.com", mode: .tunnel, endpoints: ["https://old.trycloudflare.com"])
        d.adopt(base: "https://new.trycloudflare.com")
        XCTAssertEqual(d.host, "https://new.trycloudflare.com")
        XCTAssertEqual(d.endpoints.first, "https://new.trycloudflare.com")
        XCTAssertEqual(d.baseURL?.absoluteString, "https://new.trycloudflare.com")

        d.adopt(base: "http://192.168.1.5:19876")
        XCTAssertEqual(d.host, "192.168.1.5")
        XCTAssertEqual(d.port, 19876)
        XCTAssertEqual(d.endpoints.count, 3, "换过的地址都留着，下次可以再试")

        // 同一个地址不会重复堆积
        d.adopt(base: "http://192.168.1.5:19876")
        XCTAssertEqual(d.endpoints.count, 3)
    }

    func testPairingPayloadCarriesEndpoints() throws {
        let p = try XCTUnwrap(PairingPayload(text: #"""
        {"yzvibe":1,"name":"Mac","host":"https://x.trycloudflare.com","port":null,"token":"t1","mode":"tunnel",
         "endpoints":["https://x.trycloudflare.com","http://192.168.1.5:19876",""]}
        """#))
        XCTAssertEqual(p.endpoints, ["https://x.trycloudflare.com", "http://192.168.1.5:19876"])
        XCTAssertNil(PairingPayload(text: "yzvibe://pair?host=1.2.3.4&token=t")?.endpoints)
    }

    func testHealthDecodesEndpoints() throws {
        let h = try decode(#"{"name":"Mac","version":"0.1.0","agents":["claude"],"connectorId":"c1","endpoints":["http://a:1","http://b:2"]}"#, as: HealthInfo.self)
        XCTAssertEqual(h.endpoints.count, 2)
        XCTAssertTrue(try decode(#"{"name":"Mac"}"#, as: HealthInfo.self).endpoints.isEmpty)
    }

    func testWorkingDiffDecodes() throws {
        let d = try decode(#"""
        {"repo":true,"branch":"main","head":"a1b2 上次提交","totals":{"files":2,"added":73,"removed":8},"truncated":false,
         "files":[{"path":"src/a.ts","status":"已修改","added":42,"removed":8,"diff":"-x\n+y"},
                  {"path":"src/b.ts","status":"新增","untracked":true,"added":31,"removed":0}]}
        """#, as: WorkingDiff.self)
        XCTAssertEqual(d.totals.added, 73)
        XCTAssertEqual(d.files.first?.name, "a.ts")
        XCTAssertEqual(d.files.first?.folder, "src")
        XCTAssertTrue(d.files[1].untracked)

        let none = try decode(#"{"repo":false,"reason":"这个目录不在 git 仓库里"}"#, as: WorkingDiff.self)
        XCTAssertFalse(none.repo)
        XCTAssertEqual(none.files.count, 0)
    }

    func testCommandCatalogDecodes() throws {
        let c = try decode(#"""
        {"reported":true,
         "app":[{"name":"new","args":"[提示词]","description":"新建会话","kind":"app","source":"YzVibe","action":"new-session"}],
         "agentCommands":[{"name":"compact","description":"压缩上下文","source":"Claude Code 内置"}],
         "skills":[{"name":"code-review","description":"审查改动","kind":"skill","source":"个人 skill"}],
         "prompts":[]}
        """#, as: CommandCatalog.self)
        XCTAssertTrue(c.reported)
        XCTAssertEqual(c.app.first?.action, "new-session")
        XCTAssertTrue(c.app.first!.isApp)
        XCTAssertEqual(c.app.first?.display, "/new [提示词]")
        XCTAssertEqual(c.agentCommands.first?.display, "/compact")
        XCTAssertEqual(c.agentCommands.first?.kind, "agent")
        XCTAssertFalse(c.isEmpty)
        XCTAssertTrue(try decode("{}", as: CommandCatalog.self).isEmpty)
    }

    func testLiveActivityContentState() throws {
        let s = SessionActivityAttributes.ContentState(status: "waiting_approval", headline: "等你批准：rm -rf dist", pendingApprovals: 1, queued: 2, contextPercent: 37)
        XCTAssertTrue(s.needsApproval)
        XCTAssertFalse(s.isRunning)
        XCTAssertEqual(s.shortStatus, "待批准")
        let running = SessionActivityAttributes.ContentState(status: "running", headline: "正在 Bash：npm test")
        XCTAssertTrue(running.isRunning)
        XCTAssertEqual(running.shortStatus, "运行中")
        // 连接器推过来的 content-state 由 ActivityKit 用「默认」解码器解，Date 是自 2001-01-01 起的秒数，
        // 不是 ISO8601 字符串——所以这里必须用原味 JSONDecoder 验，用错解码器就测不出真实行为。
        let json = #"{"status":"running","headline":"正在处理…","pendingApprovals":0,"queued":1,"contextPercent":12,"updatedAt":800000000}"#
        let decoded = try JSONDecoder().decode(SessionActivityAttributes.ContentState.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.queued, 1)
        XCTAssertEqual(decoded.contextPercent, 12)
        XCTAssertEqual(Int(decoded.updatedAt.timeIntervalSinceReferenceDate), 800_000_000)
        // 反过来：我们自己编码出来的也是数字，两端才对得上
        let round = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any]
        XCTAssertTrue(round?["updatedAt"] is NSNumber)
    }

    func testEndpointUpdatePushParsing() {
        let u = EndpointUpdate(userInfo: ["yz": ["kind": "endpoint", "connectorId": "c1", "name": "Mac",
                                                 "endpoints": ["https://new.trycloudflare.com", "http://192.168.1.5:19876"], "reason": "tunnel-reconnect"]])
        XCTAssertEqual(u?.connectorId, "c1")
        XCTAssertEqual(u?.endpoints.count, 2)
        XCTAssertNil(EndpointUpdate(userInfo: ["yz": ["kind": "approval"]]))
        XCTAssertNil(EndpointUpdate(userInfo: ["yz": ["kind": "endpoint", "endpoints": []]]))
    }

    /// 隧道换地址后在局域网里找回同一台电脑：认 connectorId，认不出来的（老连接器没广播 id）探 /health 验身份。
    @MainActor
    func testReconnectViaLANMatchesTheSameConnector() async {
        let client = QueueStubClient()
        let store = AppStore(client: client, seedMock: false)
        var device = Device(id: "c1", name: "Mac", host: "https://old-tunnel.trycloudflare.com", port: 443, mode: .tunnel)
        device.online = false
        store.devices = [device]
        store.selectedDeviceId = device.id

        // 广播里带了 id：直接换地址
        store.lanDiscovery = { _ in [DiscoveredConnector(connectorId: "c1", name: "Mac", base: "http://192.168.1.9:19876")] }
        var ok = await store.reconnectViaLAN(device)
        XCTAssertTrue(ok)
        XCTAssertEqual(store.device("c1")?.host, "192.168.1.9")
        XCTAssertEqual(store.device("c1")?.port, 19876)

        // 广播里没有 id：探 /health，id 对不上的那台要跳过
        store.devices = [device]
        client.healthByBase = ["http://192.168.1.7:19876": HealthInfo(name: "别人的 Mac", version: "1", agents: [], connectorId: "c2"),
                               "http://192.168.1.8:19876": HealthInfo(name: "Mac", version: "1", agents: [], connectorId: "c1")]
        store.lanDiscovery = { _ in [DiscoveredConnector(connectorId: nil, name: "A", base: "http://192.168.1.7:19876"),
                                     DiscoveredConnector(connectorId: nil, name: "B", base: "http://192.168.1.8:19876")] }
        ok = await store.reconnectViaLAN(device)
        XCTAssertTrue(ok)
        XCTAssertEqual(store.device("c1")?.host, "192.168.1.8")

        // 一台都对不上：不动原来的地址
        store.devices = [device]
        client.healthByBase = [:]
        store.lanDiscovery = { _ in [DiscoveredConnector(connectorId: "other", name: "X", base: "http://192.168.1.5:19876")] }
        ok = await store.reconnectViaLAN(device)
        XCTAssertFalse(ok)
        XCTAssertEqual(store.device("c1")?.host, "https://old-tunnel.trycloudflare.com")
    }

    /// 删除会话：本地立刻消失；连接器删失败时要把它放回来，别让列表骗人。
    @MainActor
    func testDeleteSessionRemovesLocallyAndRollsBackOnFailure() async {
        let client = QueueStubClient()
        let store = AppStore(client: client, seedMock: false)
        var device = MockData.macStudio; device.online = true
        store.devices = [device]
        store.selectedDeviceId = device.id
        let s1 = Session(id: "s1", deviceId: device.id, agent: .claude, cwd: "/p", title: "t", status: .idle)
        store.sessions = [s1]
        store.messages["s1"] = [Message(sessionId: "s1", role: .user, text: "hi")]

        await store.deleteSession("s1")
        XCTAssertEqual(client.deleted, "s1")
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertNil(store.messages["s1"])
        XCTAssertEqual(store.hiddenSessionCount[device.id], 1)

        // 删失败：refresh 会把服务端还在的会话拉回来
        client.failDelete = true
        client.sessionsOnServer = [s1]
        store.sessions = [s1]
        await store.deleteSession("s1")
        XCTAssertEqual(store.sessions.map(\.id), ["s1"])

        // 连接器广播 session.removed 时本地也要跟着清掉
        client.failDelete = false
        store.handle(.sessionRemoved(sessionId: "s1"), device: device)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    @MainActor
    func testSendQueuesWhenBusyAndCanCancel() async {
        let client = QueueStubClient()
        let store = AppStore(client: client, seedMock: false)
        var device = MockData.macStudio; device.online = true
        store.devices = [device]
        store.selectedDeviceId = device.id
        store.sessions = [Session(id: "s1", deviceId: device.id, agent: .claude, cwd: "/p", title: "t", status: .running)]

        // 忙的时候：进队列，不往消息流里塞乐观消息
        client.nextQueued = QueuedMessage(id: "q1", text: "排队一号")
        let queued = await store.send("排队一号", in: "s1")
        XCTAssertEqual(queued, .queued)
        XCTAssertEqual(store.session("s1")?.queue.map(\.text), ["排队一号"])
        XCTAssertNil(store.messages["s1"]?.first(where: { $0.text == "排队一号" }))
        XCTAssertEqual(client.lastMode, .auto)

        // 撤掉排队的
        await store.cancelQueued("q1", in: "s1")
        XCTAssertEqual(store.session("s1")?.queue.count, 0)
        XCTAssertEqual(client.cancelled, "q1")

        // 立即发送：插队 + 打断，本地立刻显示
        client.nextQueued = nil
        let now = await store.send("马上发", in: "s1", mode: .now)
        XCTAssertEqual(now, .sent)
        XCTAssertEqual(client.lastMode, .now)
        XCTAssertEqual(store.messages["s1"]?.last?.text, "马上发")
    }
}

/// 队列测试用的假连接器。
final class QueueStubClient: ConnectorClient, @unchecked Sendable {
    var endpointValidation: ((Device, String) async throws -> HealthInfo)?
    func validateEndpoint(device: Device, address: String) async throws -> HealthInfo {
        guard let endpointValidation else { throw ConnectorError.unreachable }
        return try await endpointValidation(device, address)
    }
    var deliveryHandler: ((String, String, [String]) async throws -> DeliveryReceipt)?
    var receiptHandler: ((String) async throws -> DeliveryReceipt?)?
    var uploadHandler: ((Data) async throws -> String)?
    var snapshotRequests: [[String]] = []
    func deliver(device: Device, sessionId: String, clientMessageId: String, text: String, attachments: [String], mode: SendMode) async throws -> DeliveryReceipt {
        if let deliveryHandler { return try await deliveryHandler(clientMessageId, text, attachments) }
        let response = try await sendMessage(device: device, sessionId: sessionId, text: text, attachments: attachments, mode: mode)
        return DeliveryReceipt(id: clientMessageId, itemId: response.item?.id, state: response.queued ? "queued" : "sent")
    }
    func delivery(device: Device, sessionId: String, id: String) async throws -> DeliveryReceipt? { try await receiptHandler?(id) }
    func requestSnapshot(device: Device, sessionIds: [String]) async throws -> Bool { snapshotRequests.append(sessionIds); return false }
    var messagesHandler: (@Sendable () async throws -> [Message])?
    var nextQueued: QueuedMessage?
    var lastMode: SendMode?
    var cancelled: String?
    var deleted: String?
    var failDelete = false
    var restored = 0
    var sessionsOnServer: [Session] = []
    /// base URL → 该地址上连接器的身份；用来模拟「局域网里探到的是不是那台电脑」
    var healthByBase: [String: HealthInfo] = [:]
    var probedBases: [String] = []

    func sendMessage(device: Device, sessionId: String, text: String, attachments: [String], mode: SendMode) async throws -> (queued: Bool, item: QueuedMessage?) {
        lastMode = mode
        if let q = nextQueued { return (true, q) }
        return (false, nil)
    }
    func cancelQueued(device: Device, sessionId: String, itemId: String) async throws { cancelled = itemId }
    func deleteSession(device: Device, sessionId: String) async throws {
        if failDelete { throw ConnectorError.unreachable }
        deleted = sessionId
    }
    func restoreHiddenSessions(device: Device) async throws -> Int { restored }
    func diff(device: Device, sessionId: String, scope: String) async throws -> WorkingDiff { WorkingDiff() }
    func commands(device: Device, sessionId: String) async throws -> CommandCatalog { CommandCatalog() }

    func health(device: Device) async throws -> HealthInfo {
        let base = device.host.contains("://") ? device.host : "http://\(device.host):\(device.port)"
        probedBases.append(base)
        guard let h = healthByBase[base] else { throw ConnectorError.unreachable }
        return h
    }
    func pair(_ payload: PairingPayload) async throws -> Device { MockData.macStudio }
    func sessions(device: Device) async throws -> [Session] { sessionsOnServer }
    func createSession(device: Device, request: NewSessionRequest) async throws -> Session { MockData.sessions[0] }
    func messages(device: Device, sessionId: String, after cursor: String?) async throws -> [Message] { try await messagesHandler?() ?? [] }
    func send(device: Device, sessionId: String, text: String, attachments: [String]) async throws {}
    func stop(device: Device, sessionId: String) async throws {}
    func respond(device: Device, approvalId: String, decision: ApprovalDecision, remember: ApprovalSuggestion?, answers: [String: String]?) async throws {}
    func approvals(device: Device) async throws -> [Approval] { [] }
    func capabilities(device: Device) async throws -> [String: AgentCapabilities] { [:] }
    func configure(device: Device, sessionId: String, patch: [String: String?]) async throws -> Session { MockData.sessions[0] }
    func quota(device: Device, agent: AgentKind) async throws -> QuotaInfo { QuotaInfo(agent: agent.rawValue) }
    func fileInfo(device: Device, sessionId: String, path: String) async throws -> FileInfo { throw ConnectorError.unreachable }
    func download(device: Device, sessionId: String, path: String) async throws -> Data { Data() }
    func attachment(device: Device, id: String) async throws -> Data { Data() }
    func listFiles(device: Device, sessionId: String, path: String) async throws -> [FileEntry] { [] }
    func preview(device: Device, sessionId: String, path: String) async throws -> String { "" }
    func upload(device: Device, data: Data, mime: String, filename: String) async throws -> String { try await uploadHandler?(data) ?? "u1" }
    func listDirectories(device: Device, path: String?) async throws -> DirectoryListing { DirectoryListing(path: "/", parent: nil, home: "/", entries: []) }
    func makeDirectory(device: Device, parent: String, name: String) async throws -> String { parent }
    func sync(device: Device) async throws -> SyncSnapshot { SyncSnapshot() }
    func rules(device: Device, sessionId: String?) async throws -> [ApprovalRule] { [] }
    func deleteRule(device: Device, id: String) async throws {}
    func registerPush(device: Device, token: String, environment: String) async throws -> PushStatus { PushStatus() }
    func unregisterPush(device: Device) async throws {}
    func registerLiveActivity(device: Device, sessionId: String, token: String) async throws {}
    func reconnect(device: Device) {}
    func events(device: Device) -> AsyncStream<ConnectorEvent> { AsyncStream { $0.finish() } }
}
