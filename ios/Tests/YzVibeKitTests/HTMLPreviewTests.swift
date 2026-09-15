import Foundation
import Testing
import WebKit
import UIKit
@testable import YzVibeKit

@Suite @MainActor struct HTMLPreviewTests {
    @Test func rendersRelativeStylesImagesAndScriptsWithoutConnectorOrigin() async throws {
        let resources: [String: (Data, String)] = [
            "index.html": (Data("<html><head><link rel='stylesheet' href='assets/style.css'></head><body><h1>Preview</h1><img id='art' src='assets/art.svg'><button id='button' onclick=\"document.querySelector('h1').textContent='Clicked'\">Click</button><script src='assets/app.js'></script></body></html>".utf8), "text/html"),
            "assets/style.css": (Data("h1{color:rgb(192,75,0)}".utf8), "text/css"),
            "assets/app.js": (Data("document.title='Scripts ready'".utf8), "text/javascript"),
            "assets/art.svg": (Data("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><rect width='10' height='10' fill='orange'/></svg>".utf8), "image/svg+xml")
        ]
        let preview = HTMLPreview(entry: "/remote/site/index.html", resource: { path in
            guard let value = resources[path] else { throw URLError(.fileDoesNotExist) }
            return value
        }, onError: { Issue.record(Comment(rawValue: $0)) })
        let coordinator = preview.makeCoordinator()
        let web = preview.makeWebView(coordinator: coordinator)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController(); window.rootViewController = controller
        controller.view.addSubview(web); web.frame = window.bounds; window.makeKeyAndVisible()
        defer { web.stopLoading(); coordinator.cancelAll(); window.isHidden = true }
        var ready = false
        for _ in 0..<100 {
            let value = try? await web.evaluateJavaScript("document.title === 'Scripts ready' && document.querySelector('#art').naturalWidth > 0")
            if value as? Bool == true { ready = true; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(ready)
        let color = try await web.evaluateJavaScript("getComputedStyle(document.querySelector('h1')).color") as? String
        #expect(color == "rgb(192, 75, 0)")
        _ = try await web.evaluateJavaScript("document.querySelector('#button').click()")
        let text = try await web.evaluateJavaScript("document.querySelector('h1').textContent") as? String
        #expect(text == "Clicked")
        #expect(web.url?.scheme == "yzpreview")
        #expect(web.configuration.websiteDataStore.isPersistent == false)
    }
}
