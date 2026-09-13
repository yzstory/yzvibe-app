import Foundation

public struct NotificationPreferences: Codable, Sendable, Equatable {
    public var notifyOnApproval: Bool
    public var notifyOnReply: Bool
}

public struct RunCompletion: Decodable, Sendable {
    public var sessionId: String
    public var runId: String
    public var messageId: String
    public var text: String
    public var remote: Bool
}

extension AppStore {
    /// Serialize writes so a slow earlier request cannot overwrite a later toggle.
    public func syncNotificationPreferences() {
        guard !isDemo else { return }
        notificationSyncPending = true
        guard notificationSyncTask == nil else { return }
        notificationSyncTask = Task { [weak self] in
            guard let self else { return }
            defer { notificationSyncTask = nil }
            while notificationSyncPending {
                notificationSyncPending = false
                let preferences = NotificationPreferences(notifyOnApproval: settings.notifyOnApproval, notifyOnReply: settings.notifyOnReply)
                for device in devices {
                    do {
                        try await client.updateNotifications(device: device, preferences: preferences)
                        notificationSyncErrors.removeValue(forKey: device.id)
                    } catch {
                        notificationSyncErrors[device.id] = error.localizedDescription
                    }
                }
            }
        }
    }

    func notifyCompletion(_ completion: RunCompletion) {
        let key = "\(completion.sessionId):\(completion.runId)"
        guard !notifiedRuns.contains(key) else { return }
        notifiedRuns.append(key)
        if notifiedRuns.count > 200 { notifiedRuns.removeFirst(notifiedRuns.count - 200) }
        guard settings.notifyOnReply, !completion.remote,
              let session = session(completion.sessionId), !completion.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        postCompletionNotification("\(session.agent.displayName) 回复完成", "\(session.title)\n\(completion.text.prefix(150))", "reply-\(completion.runId)")
    }
}
