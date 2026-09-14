import Foundation

/// Local paths refer to the paired Mac, never the iPhone filesystem.
enum RemoteFileReference {
    static func link(_ path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "yzfile"; components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        return components.url
    }
    static func path(from url: URL, relativeTo directory: String? = nil) -> String? {
        let raw: String
        switch url.scheme?.lowercased() {
        case "yzfile":
            guard let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "path" })?.value else { return nil }
            raw = value
        case "file":
            guard url.host == nil || url.host == "" || url.host == "localhost" else { return nil }
            raw = url.path
        case "sandbox": raw = url.path
        case nil:
            guard url.host == nil, !url.path.isEmpty else { return nil }
            raw = url.path
        default: return nil
        }
        return resolve(raw, relativeTo: directory)
    }
    static func resolve(_ raw: String, relativeTo directory: String? = nil) -> String {
        // Codex source citations may suffix a line number; preserve other colons in names.
        let path = raw.replacingOccurrences(of: #":\d+(?::\d+)?$|#L\d+(?:-L?\d+)?$"#, with: "", options: .regularExpression)
        guard let directory, !path.hasPrefix("/"), !path.hasPrefix("~/") else { return path }
        return ((directory as NSString).appendingPathComponent(path) as NSString).standardizingPath
    }
    static func imagePath(_ raw: String, relativeTo directory: String?) -> String {
        guard let url = URL(string: raw), let path = path(from: url, relativeTo: directory) else { return raw }
        return path
    }
}
