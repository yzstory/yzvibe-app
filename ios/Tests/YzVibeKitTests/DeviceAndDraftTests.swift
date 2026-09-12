import Testing
import UIKit
@testable import YzVibeKit

@MainActor struct DeviceAndDraftTests {
    @Test func configurationKeepsPairingIdentityAndRetainsAlternativeEndpoints() throws {
        let original = MockData.macStudio
        var form = DeviceConfiguration(original)
        form.name = "工作电脑"
        form.address = "https://new.example.com:8443"
        let updated = try #require(form.applying(to: original))
        #expect(updated.id == original.id)
        #expect(updated.name == "工作电脑")
        #expect(updated.port == 8443)
        #expect(updated.endpoints == ["https://new.example.com:8443"] + EndpointAddress.candidates(original))
        form.address = "192.168.1.20"; form.port = "19876"
        #expect(form.applying(to: original)?.baseURL?.absoluteString == "http://192.168.1.20:19876")
        for invalid in ["file:///tmp/test", "https://user:secret@example.com", "https://example.com?token=secret", ""] {
            form.address = invalid
            #expect(form.applying(to: original) == nil)
        }
        form.address = "localhost"; form.port = "99999"
        #expect(form.applying(to: original) == nil)
    }

    @Test func draftsKeepTextAndImagesSeparateAcrossSessions() {
        let store = AppStore()
        let image = PendingImage(data: Data([1, 2]), image: UIImage())
        store.chatDrafts["first", default: ChatDraft()].text = "未发送"
        store.chatDrafts["first", default: ChatDraft()].images = [image]
        store.chatDrafts["second", default: ChatDraft()].text = "另一个草稿"
        #expect(store.chatDrafts["first"]?.text == "未发送")
        #expect(store.chatDrafts["first"]?.images == [image])
        store.chatDrafts["second"] = nil
        #expect(store.chatDrafts["first"]?.images.first?.data == Data([1, 2]))
    }
}
