import Foundation
import CryptoKit

/// Disposable history cache; serialization and disk IO stay off the UI actor.
actor MessageCache {
    struct Record: Codable { let device: String; let session: String; let messages: [Message] }
    let directory: URL
    let budget: Int
    init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MessageHistory-v1"), budget: Int = 100 * 1024 * 1024) {
        self.directory = directory; self.budget = budget
    }
    private func url(_ device: String, _ session: String) -> URL {
        let key = SHA256.hash(data: Data((device + "\n" + session).utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key).appendingPathExtension("json")
    }
    func load(device: String, session: String) -> [Message]? {
        let target = url(device, session)
        guard let size = try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= budget,
              let data = try? Data(contentsOf: target),
              let record = try? JSONDecoder().decode(Record.self, from: data), record.device == device, record.session == session else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: target.path)
        return record.messages
    }
    func save(device: String, session: String, messages: [Message]) {
        guard let data = try? JSONEncoder().encode(Record(device: device, session: session, messages: messages)), data.count <= budget else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url(device, session), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
            let entries = files.compactMap { file -> (URL, Int, Date)? in
                guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
                return (file, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
            }.sorted { $0.2 < $1.2 }
            var total = entries.reduce(0) { $0 + $1.1 }
            for entry in entries where total > budget { try? FileManager.default.removeItem(at: entry.0); total -= entry.1 }
        } catch { /* A cache failure must never prevent receiving/sending messages. */ }
    }
    func remove(device: String, session: String) { try? FileManager.default.removeItem(at: url(device, session)) }
}
