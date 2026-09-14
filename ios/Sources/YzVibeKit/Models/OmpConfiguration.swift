import Foundation

public struct OmpConfiguration: Codable, Sendable {
    public var revision: String
    public var models: [OmpConfiguredModel]
}
public struct OmpConfiguredModel: Codable, Sendable, Identifiable {
    public var id: String
    public var providerId: String
    public var modelName: String
    public var label: String
    public var baseUrl: String
    public var keyConfigured: Bool
    public var editable: Bool
}
public struct OmpConfigurationInput: Encodable, Sendable {
    public var revision: String
    public var providerId: String?
    public var originalModelName: String?
    public var baseUrl: String
    public var key: String
    public var modelName: String
}
