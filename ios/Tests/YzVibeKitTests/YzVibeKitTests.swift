import XCTest
import UIKit
@testable import YzVibeKit

final class YzVibeKitTests: XCTestCase {
    func testOKLCHBrandConvertsToWarmRed() {
        let s = OKLCH(0.64, 0.17, 40).srgb
        XCTAssertGreaterThan(s.r, s.g)
        XCTAssertGreaterThan(s.g, s.b)
        XCTAssertEqual(s.r, 0.87, accuracy: 0.05)   // oklch(0.64 0.17 40) ≈ rgb(221, 110, 76)
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
