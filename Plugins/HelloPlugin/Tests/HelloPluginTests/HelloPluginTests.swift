import Foundation
import IsletCore
import Testing
@testable import HelloPlugin

@MainActor
struct HelloPluginTests {
    @Test func activatesWithTheCompactSizeAndNoStoredGreeting() async throws {
        let suite = "HelloPluginTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        defer { try? FileManager.default.removeItem(at: root) }

        let registry = PluginRegistry(storageRoot: root, userDefaults: defaults)
        let entry = try await registry.register(HelloPlugin.self)
        #expect(entry.state.isActive)
        #expect(entry.context.contentSize == HelloScreen.compactSize)
        let greeting: String? = entry.context.settings.value(forKey: HelloPlugin.greetingKey)
        #expect(greeting == nil)
        await registry.deactivateAll()
    }
}
