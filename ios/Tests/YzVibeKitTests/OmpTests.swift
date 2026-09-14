import Foundation
import Testing
@testable import YzVibeKit

@Suite struct OmpTests {
    @Test func providerModelsKeepTheirOwnEfforts() throws {
        let json = #"{"modes":{},"efforts":["high"],"models":[{"id":"gateway/qwen","label":"Qwen","efforts":[]},{"id":"other/model","label":"Other","efforts":["low","high"]}],"customModel":false}"#
        let caps = try JSONDecoder().decode(AgentCapabilities.self, from: Data(json.utf8))
        #expect(caps.efforts(for: "gateway/qwen").isEmpty)
        #expect(caps.efforts(for: "other/model") == ["low", "high"])
        #expect(!caps.customModel)
        #expect(try JSONDecoder().decode(AgentKind.self, from: Data(#""omp""#.utf8)) == .omp)
    }
    @Test func missingOmpCatalogDoesNotInventModels() {
        let caps = AgentCapabilities.fallback(for: .omp)
        #expect(caps.models.isEmpty)
        #expect(caps.efforts.isEmpty)
        #expect(!caps.customModel)
    }

    @Test @MainActor func ompIgnoresPhonePresetsAndCustomIsNotCreatable() {
        #expect(AgentKind.supported == [.claude, .codex, .omp])
        let store = AppStore()
        store.settings.setModelPresets([ModelOption(id: "xai/grok-old")], for: .omp)
        #expect(store.modelOptions(for: .omp, caps: .fallback(for: .omp)).isEmpty)
    }
    @Test func keySaveRejectsHTTPBeforeSending() async {
        let client = HTTPConnectorClient(tokenProvider: { _ in "test" })
        let device = Device(id: "fixture", name: "Mac", host: "http://127.0.0.1", port: 19876, mode: .local)
        let input = OmpConfigurationInput(revision: "revision", baseUrl: "https://example.com/v1", key: "test", modelName: "test")
        do {
            _ = try await client.saveOmpConfiguration(device: device, input: input)
            Issue.record("Expected HTTPS requirement")
        } catch { #expect(error.localizedDescription.contains("HTTPS")) }
    }
}
