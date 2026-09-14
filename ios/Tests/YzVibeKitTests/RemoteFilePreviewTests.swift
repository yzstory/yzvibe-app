import Foundation
import SwiftUI
import Testing
@testable import YzVibeKit

@Suite struct RemoteFilePreviewTests {
    @Test func pathsRoundTripReservedCharactersAndLineReferences() throws {
        let original = "/Users/yuki/设计 A&B/报告 #1.md"
        let url = try #require(RemoteFileReference.link(original))
        #expect(RemoteFileReference.path(from: url) == original)
        #expect(RemoteFileReference.path(from: URL(string: "file:///Users/yuki/My%20Report.md")!) == "/Users/yuki/My Report.md")
        #expect(RemoteFileReference.path(from: URL(string: "sandbox:/tmp/result.mp4")!) == "/tmp/result.mp4")
        #expect(FilePathDetector.path(in: "src/view.swift:12:3") == "src/view.swift")
        #expect(FilePathDetector.path(in: "/tmp/my clip.mp4") == "/tmp/my clip.mp4")
    }
    @Test func documentLinksResolveFromDocumentDirectoryAndExternalLinksStayExternal() {
        #expect(RemoteFileReference.path(from: URL(string: "../images/a.png")!, relativeTo: "/Users/yuki/project/docs") == "/Users/yuki/project/images/a.png")
        #expect(RemoteFileReference.path(from: URL(string: "https://example.com/report.md")!, relativeTo: "/tmp") == nil)
        #expect(RemoteFileReference.path(from: URL(string: "file://other-host/report.md")!) == nil)
        #expect(RemoteFileReference.imagePath("assets/a%20b.png", relativeTo: "/tmp/docs") == "/tmp/docs/assets/a b.png")
    }
    @Test func prosePathsBecomeLinksWithoutHijackingWebLinks() {
        let input = AttributedString("查看 /tmp/截图.png、docs/report.md 和 movie.mp4；https://example.com/report.md")
        let output = MarkdownText.linkifyPaths(input, tint: .orange)
        let paths = output.runs.compactMap { $0.link.flatMap { RemoteFileReference.path(from: $0) } }
        #expect(paths == ["/tmp/截图.png", "docs/report.md", "movie.mp4"])
        #expect(FilePathDetector.plainPaths(in: "file:///tmp/demo.mov").first?.path == "/tmp/demo.mov")
    }
    @Test func explicitMarkdownLocalLinkKeepsItsTarget() throws {
        let text = try AttributedString(markdown: "[打开文档](<docs/My Report.md>)")
        let url = try #require(text.runs.first?.link)
        #expect(RemoteFileReference.path(from: url, relativeTo: "/tmp/project") == "/tmp/project/docs/My Report.md")
    }
}
