import Foundation
import UIKit

@MainActor
extension AppStore {
    /// This is synchronous so a second tap cannot stage the same composer contents twice.
    func stageDraft(in sessionId: String, mode: SendMode) -> String? {
        let draft = chatDrafts[sessionId] ?? ChatDraft()
        guard let id = stageMessage(draft.text, in: sessionId, images: draft.images.map { OutgoingImage(data: $0.data) }, mode: mode) else { return nil }
        chatDrafts[sessionId] = ChatDraft()
        return id
    }

    func stageMessage(_ text: String, in sessionId: String, images: [OutgoingImage], attachments: [String] = [], mode: SendMode) -> String? {
        guard let session = session(sessionId) else { return nil }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !images.isEmpty || !attachments.isEmpty else { return nil }
        guard outbox.count < 100, images.count + attachments.count <= 6,
              images.reduce(0, { $0 + $1.data.count }) <= 20 * 1024 * 1024 else {
            toast = "待发送箱已满或图片过大，请处理已有内容后再发送。"; return nil
        }
        let item = OutgoingMessage(deviceId: session.deviceId, sessionId: sessionId, text: text, images: images, attachments: attachments, mode: mode.rawValue)
        do { try saveOutbox(outbox + [item]); return item.id }
        catch { toast = "未能保存待发送内容，输入已保留：\(error.localizedDescription)"; return nil }
    }

    func saveOutbox(_ value: [OutgoingMessage]) throws {
        guard !outboxLoadFailed else { throw ConnectorError.network("待发送箱原记录无法读取，请先处理存储问题") }
        try outboxDisk?.save(value)
        outbox = value
    }

    private func updateOutgoing(_ id: String, _ change: (inout OutgoingMessage) -> Void) throws {
        var next = outbox
        guard let index = next.firstIndex(where: { $0.id == id }) else { return }
        change(&next[index])
        try saveOutbox(next)
    }

    @discardableResult
    func transmit(_ id: String) async -> SendOutcome {
        guard let original = outbox.first(where: { $0.id == id }), let device = device(original.deviceId), sendingIDs.insert(id).inserted else { return .failed }
        defer { sendingIDs.remove(id) }
        var attemptedDelivery = original.state == .uncertain || original.state == .sending
        do {
            try updateOutgoing(id) { $0.state = .sending; $0.issue = nil }
            // A retry first reconciles receipt state. A missing receipt is the only reason to send again.
            if let receipt = try await client.delivery(device: device, sessionId: original.sessionId, id: id) {
                let outcome = try acceptReceipt(receipt, for: original)
                _ = try? await client.requestSnapshot(device: device, sessionIds: [original.sessionId])
                return outcome
            }
            attemptedDelivery = false
            try updateOutgoing(id) { $0.state = .uploading; $0.issue = nil }
            for index in original.images.indices {
                guard let current = outbox.first(where: { $0.id == id }) else { return .failed }
                if current.images[index].uploadId != nil { continue }
                let image = current.images[index]
                let upload = try await client.upload(device: device, data: image.data, mime: "image/jpeg", filename: "photo.jpg")
                try updateOutgoing(id) { $0.images[index].uploadId = upload }
                if let image = UIImage(data: image.data) { cacheAttachment(image, id: upload) }
            }
            guard let ready = outbox.first(where: { $0.id == id }), ready.images.allSatisfy({ $0.uploadId != nil }) else { return .failed }
            try updateOutgoing(id) { $0.state = .sending }
            attemptedDelivery = true
            let receipt = try await client.deliver(device: device, sessionId: ready.sessionId, clientMessageId: id, text: ready.text,
                                                   attachments: ready.attachments + ready.images.compactMap(\.uploadId), mode: SendMode(rawValue: ready.mode) ?? .auto)
            let outcome = try acceptReceipt(receipt, for: ready)
            _ = try? await client.requestSnapshot(device: device, sessionIds: [ready.sessionId])
            return outcome
        } catch {
            var definiteFailure = !attemptedDelivery
            var missingImages = false
            if case ConnectorError.server(let status, let code, _) = error {
                definiteFailure = (400..<500).contains(status)
                missingImages = code == "attachment_missing"
            }
            let issue = definiteFailure ? error.localizedDescription : "发送结果待确认；重试会先核对电脑记录，不会直接再执行。"
            do {
                try updateOutgoing(id) {
                    $0.state = definiteFailure ? .failed : .uncertain; $0.issue = issue
                    if missingImages { for i in $0.images.indices { $0.images[i].uploadId = nil } }
                }
            } catch { toast = "发送记录未能更新，重启后请先核对接收状态。" }
            if toast == nil { toast = issue }
            return .failed
        }
    }

    private func acceptReceipt(_ receipt: DeliveryReceipt, for item: OutgoingMessage) throws -> SendOutcome {
        guard receipt.id == item.id else { throw ConnectorError.decoding }
        switch receipt.state {
        case "queued", "sent":
            try saveOutbox(outbox.filter { $0.id != item.id })
            let attachments = item.attachments + item.images.compactMap(\.uploadId)
            if receipt.state == "queued", let queueID = receipt.itemId, let index = sessions.firstIndex(where: { $0.id == item.sessionId }),
               !sessions[index].queue.contains(where: { $0.id == queueID }), !(messages[item.sessionId] ?? []).contains(where: { $0.clientMessageId == item.id }) {
                sessions[index].queue.append(QueuedMessage(id: queueID, text: item.text, attachments: attachments, createdAt: item.createdAt))
            } else if receipt.state == "sent", !(messages[item.sessionId] ?? []).contains(where: { $0.clientMessageId == item.id }) {
                var message = Message(sessionId: item.sessionId, role: .user, text: item.text, attachments: attachments, createdAt: item.createdAt, isLocal: true)
                message.clientMessageId = item.id
                messages[item.sessionId, default: []].append(message)
            }
            return receipt.state == "queued" ? .queued : .sent
        case "cancelled":
            try saveOutbox(outbox.filter { $0.id != item.id }); toast = "这条消息已在电脑队列中取消"; return .failed
        default:
            try updateOutgoing(item.id) { $0.state = .uncertain; $0.issue = "电脑已接收，Agent 接收结果待确认。请查看会话与队列后再继续。" }
            return .failed
        }
    }

    func reconcileOutbox(_ device: Device) async {
        var reconciled: Set<String> = []
        for item in outbox.filter({ $0.deviceId == device.id && !sendingIDs.contains($0.id) }) {
            do {
                if let receipt = try await client.delivery(device: device, sessionId: item.sessionId, id: item.id) {
                    _ = try acceptReceipt(receipt, for: item)
                    if !outbox.contains(where: { $0.id == item.id }) { reconciled.insert(item.sessionId) }
                }
            } catch { /* A failed read never initiates delivery or removes local content. */ }
        }
        if !reconciled.isEmpty { _ = try? await client.requestSnapshot(device: device, sessionIds: Array(reconciled)) }
    }

    func restoreOutgoing(_ id: String) {
        guard let item = outbox.first(where: { $0.id == id }), item.state == .failed, !sendingIDs.contains(id) else { return }
        guard (chatDrafts[item.sessionId]?.text ?? "").isEmpty, (chatDrafts[item.sessionId]?.images ?? []).isEmpty else {
            toast = "输入框已有内容，请先处理当前草稿。"; return
        }
        do {
            // Recreate the composer only for requests known not to have been dispatched.
            try saveOutbox(outbox.filter { $0.id != id })
            chatDrafts[item.sessionId] = ChatDraft(text: item.text, images: item.images.compactMap { image in
                guard let decoded = UIImage(data: image.data) else { return nil }
                return PendingImage(data: image.data, image: decoded)
            })
        } catch { toast = error.localizedDescription }
    }

    func loadRuns(_ sessionId: String) async {
        guard let session = session(sessionId), let device = device(session.deviceId) else { return }
        do { taskRuns[sessionId] = try await client.runs(device: device, sessionId: sessionId); runErrors[sessionId] = nil }
        catch { runErrors[sessionId] = "执行记录暂时无法读取，请刷新重试。" }
    }
}
