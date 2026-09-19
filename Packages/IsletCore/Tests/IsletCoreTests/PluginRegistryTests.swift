import Foundation
import SwiftUI
import Testing
@testable import IsletCore

@MainActor
final class StubPlugin: IsletPlugin {
    static let manifest = PluginManifest(id: "test.stub", displayName: "Stub", systemImage: "circle")
    static var activations = 0
    static var deactivations = 0

    let context: PluginContext

    init(context: PluginContext) {
        self.context = context
    }

    func activate() async { Self.activations += 1 }
    func deactivate() async { Self.deactivations += 1 }
    func makeScreen() -> AnyView { AnyView(Text("stub")) }
}

@MainActor
final class SecondPlugin: IsletPlugin {
    static let manifest = PluginManifest(id: "test.second", displayName: "Second", systemImage: "square")
    let context: PluginContext

    init(context: PluginContext) {
        self.context = context
    }

    func makeScreen() -> AnyView { AnyView(Text("second")) }
}

@MainActor
private func makeRegistry() -> PluginRegistry {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    defaults.removePersistentDomain(forName: defaults.description)
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    return PluginRegistry(storageRoot: root, userDefaults: defaults)
}

@Suite(.serialized)
@MainActor
struct PluginRegistryTests {
    @Test func registeringActivatesAndSelectsFirstPlugin() async {
        let registry = makeRegistry()
        let before = StubPlugin.activations

        let entry = await registry.register(StubPlugin.self)

        #expect(entry.manifest == StubPlugin.manifest)
        #expect(StubPlugin.activations == before + 1)
        #expect(registry.selectedID == "test.stub")
        #expect(entry.context.storageDirectory.lastPathComponent == "test.stub")
    }

    @Test func disablingDeactivatesClearsPillAndMovesSelection() async {
        let registry = makeRegistry()
        let stub = await registry.register(StubPlugin.self)
        await registry.register(SecondPlugin.self)
        stub.context.pillStatus = PillStatus(text: "busy")
        let before = StubPlugin.deactivations

        await registry.setEnabled(false, for: "test.stub")

        #expect(StubPlugin.deactivations == before + 1)
        #expect(stub.context.pillStatus == nil)
        #expect(registry.selectedID == "test.second")
        #expect(registry.enabledEntries.map(\.id) == ["test.second"])
    }

    @Test func disabledStateIsPersistedAcrossRegistries() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let first = PluginRegistry(storageRoot: root, userDefaults: defaults)
        await first.register(StubPlugin.self)
        await first.setEnabled(false, for: "test.stub")
        let before = StubPlugin.activations

        let second = PluginRegistry(storageRoot: root, userDefaults: defaults)
        await second.register(StubPlugin.self)

        #expect(!second.isEnabled("test.stub"))
        #expect(StubPlugin.activations == before)
        #expect(second.selectedID == nil)
    }

    @Test func activePillPicksHighestPriority() async {
        let registry = makeRegistry()
        let stub = await registry.register(StubPlugin.self)
        let second = await registry.register(SecondPlugin.self)

        #expect(registry.activePill == nil)

        stub.context.pillStatus = PillStatus(text: "song", priority: .ambient)
        second.context.pillStatus = PillStatus(text: "approve?", priority: .urgent)
        #expect(registry.activePill?.text == "approve?")

        await registry.setEnabled(false, for: "test.second")
        #expect(registry.activePill?.text == "song")
    }
}
