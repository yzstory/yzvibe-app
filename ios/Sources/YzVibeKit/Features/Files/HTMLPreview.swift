import SwiftUI
import WebKit

/// Isolated origin: relative resources use authenticated native transport; credentials never enter WebKit.
struct HTMLPreview: UIViewRepresentable {
    let entry: String
    let resource: @Sendable (String) async throws -> (Data, String)
    let onError: (String) -> Void
    private static let scheme = "yzpreview"
    private static let host = "page"

    func makeCoordinator() -> Coordinator { Coordinator(resource: resource, onError: onError) }
    func makeUIView(context: Context) -> WKWebView { makeWebView(coordinator: context.coordinator) }
    func makeWebView(coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(coordinator, forURLScheme: Self.scheme)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = coordinator
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.isScrollEnabled = true
        var url = URLComponents()
        url.scheme = Self.scheme; url.host = Self.host
        url.path = "/" + (entry as NSString).lastPathComponent
        if let target = url.url { web.load(URLRequest(url: target)) }
        return web
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading(); view.navigationDelegate = nil
        coordinator.cancelAll()
    }

    @MainActor final class Coordinator: NSObject, WKURLSchemeHandler, WKNavigationDelegate {
        let resource: @Sendable (String) async throws -> (Data, String)
        let onError: (String) -> Void
        var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
        // No arbitrary network, frames, forms or native bridges. Local JavaScript is for page interaction.
        static let policy = "default-src yzpreview: data: blob:; script-src yzpreview: 'unsafe-inline' 'unsafe-eval'; style-src yzpreview: 'unsafe-inline'; connect-src yzpreview:; frame-src 'none'; object-src 'none'; form-action 'none'; base-uri 'none'"
        init(resource: @escaping @Sendable (String) async throws -> (Data, String), onError: @escaping (String) -> Void) {
            self.resource = resource; self.onError = onError
        }
        func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
            let id = ObjectIdentifier(urlSchemeTask)
            guard let url = urlSchemeTask.request.url, url.scheme == HTMLPreview.scheme, url.host == HTMLPreview.host,
                  urlSchemeTask.request.httpMethod == "GET" else {
                urlSchemeTask.didFailWithError(URLError(.unsupportedURL)); return
            }
            tasks[id] = Task {
                defer { tasks[id] = nil }
                do {
                    let (original, mime) = try await resource(String(url.path.dropFirst()))
                    try Task.checkCancellation()
                    var bytes = original
                    if mime == "text/html", let text = String(data: original, encoding: .utf8) {
                        // Put policy before any author-supplied resource or script.
                        bytes = Data(("<meta http-equiv=\"Content-Security-Policy\" content=\"\(Self.policy)\">" + text).utf8)
                    }
                    let response = URLResponse(url: url, mimeType: mime, expectedContentLength: bytes.count, textEncodingName: "utf-8")
                    urlSchemeTask.didReceive(response)
                    urlSchemeTask.didReceive(bytes)
                    urlSchemeTask.didFinish()
                } catch {
                    guard !Task.isCancelled else { return }
                    urlSchemeTask.didFailWithError(error)
                    onError(error.localizedDescription)
                }
            }
        }
        func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
            tasks.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
        }
        func cancelAll() { tasks.values.forEach { $0.cancel() }; tasks.removeAll() }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            let url = action.request.url
            decisionHandler(url?.scheme == HTMLPreview.scheme && url?.host == HTMLPreview.host ? .allow : .cancel)
        }
    }
}
