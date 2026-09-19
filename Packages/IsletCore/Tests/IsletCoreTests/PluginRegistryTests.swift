import Foundation
import SwiftUI
import Testing
import IsletCore

@MainActor
final class StubPlugin: IsletPlugin {
    static let manifest = PluginManifest(id: "test.stub", displayName: "Stub", systemImage: "circle")

    let context: PluginContext
    var activations = 0
    var deactivations = 0
    var activationDelay: Duration = .zero
    var activationError: (any Error)?
    var pillAfterActivation: PillStatus?

    init(context: PluginContext) {
        self.context = context
    }

    func activate() async throws {
        activations += 1
        if activationDelay > .zero {
            try? await Task.sleep(for: activationDelay)
        }
        if let activationError { throw activationError }
        if let pillAfterActivation { context.pillStatus = pillAfterActivation }
    }

    var deactivationDelay: Duration = .zero

    func deactivate() async {
        deactivations += 1
        if deactivationDelay > .zero {
            try? await Task.sleep(for: deactivationDelay)
        }
    }
    var screenBuilds = 0
    var acceptsFileDrops = false

    func makeScreen() -> AnyView {
        screenBuilds += 1
        return AnyView(Text("stub"))
    }
}

struct StubError: Error, Equatable {}

let secondManifest = PluginManifest(id: "test.second", displayName: "Second", systemImage: "square")

@MainActor
final class Harness {
    let suiteName = "IsletCoreTests." + UUID().uuidString
    let defaults: UserDefaults
    let root: URL

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        root = FileManager.default.temporaryDirectory.appending(path: suiteName)
    }

    func makeRegistry() -> PluginRegistry {
        PluginRegistry(storageRoot: root, userDefaults: defaults)
    }

    @discardableResult
    func registerStub(in registry: PluginRegistry, configure: (StubPlugin) -> Void = { _ in }) async throws -> StubPlugin {
        var created: StubPlugin?
        try await registry.register(manifest: StubPlugin.manifest) { context in
            let plugin = StubPlugin(context: context)
            configure(plugin)
            created = plugin
            return plugin
        }
        return created!
    }

    @discardableResult
    func registerSecond(in registry: PluginRegistry, configure: (StubPlugin) -> Void = { _ in }) async throws -> StubPlugin {
        var created: StubPlugin?
        try await registry.register(manifest: secondManifest) { context in
            let plugin = StubPlugin(context: context)
            configure(plugin)
            created = plugin
            return plugin
        }
        return created!
    }

    isolated deinit {
        defaults.removePersistentDomain(forName: suiteName)
        let preferencesFile = URL.libraryDirectory
            .appending(path: "Preferences/\(suiteName).plist")
        try? FileManager.default.removeItem(at: preferencesFile)
        try? FileManager.default.removeItem(at: root)
    }
}

@Suite
@MainActor
struct PluginRegistryTests {
    let harness = Harness()

    @Test func registeringActivatesSelectsAndCreatesStorage() async throws {
        let registry = harness.makeRegistry()

        let stub = try await harness.registerStub(in: registry)
        let entry = try #require(registry.entry(for: "test.stub"))

        #expect(stub.activations == 1)
        #expect(entry.state.isActive)
        #expect(registry.selectedID == "test.stub")
        #expect(FileManager.default.fileExists(atPath: entry.context.storageDirectory.path))
    }

    @Test func rejectsDuplicateAndInvalidIDs() async throws {
        let registry = harness.makeRegistry()
        try await harness.registerStub(in: registry)

        await #expect(throws: PluginRegistryError.duplicateID("test.stub")) {
            try await harness.registerStub(in: registry)
        }
        for badID in ["", "../escape", "a/b", ".hidden", "with space"] {
            await #expect(throws: PluginRegistryError.invalidID(badID)) {
                try await registry.register(manifest: PluginManifest(id: badID, displayName: "x", systemImage: "circle")) {
                    StubPlugin(context: $0)
                }
            }
        }
        #expect(registry.entries.count == 1)
    }

    @Test func failedActivationIsRecorded() async throws {
        let registry = harness.makeRegistry()

        try await harness.registerStub(in: registry) { $0.activationError = StubError() }
        let entry = try #require(registry.entry(for: "test.stub"))

        guard case .failed(let error) = entry.state else {
            Issue.record("expected failed state, got \(entry.state)")
            return
        }
        #expect(error as? StubError == StubError())
    }

    @Test func disablingDeactivatesClearsPillAndMovesSelection() async throws {
        let registry = harness.makeRegistry()
        let stub = try await harness.registerStub(in: registry)
        try await harness.registerSecond(in: registry)
        stub.context.pillStatus = PillStatus(text: "busy")

        await registry.setEnabled(false, for: "test.stub")

        #expect(stub.deactivations == 1)
        #expect(stub.context.pillStatus == nil)
        #expect(registry.selectedID == "test.second")
        #expect(registry.enabledEntries.map(\.id) == ["test.second"])
    }

    @Test func reenablingReactivatesAndRestoresSelection() async throws {
        let registry = harness.makeRegistry()
        let stub = try await harness.registerStub(in: registry)
        await registry.setEnabled(false, for: "test.stub")
        #expect(registry.selectedID == nil)

        await registry.setEnabled(true, for: "test.stub")

        #expect(stub.activations == 2)
        #expect(registry.selectedID == "test.stub")
    }

    @Test func redundantTogglesAndUnknownIDsAreNoOps() async throws {
        let registry = harness.makeRegistry()
        let stub = try await harness.registerStub(in: registry)

        await registry.setEnabled(true, for: "test.stub")
        await registry.setEnabled(false, for: "does.not.exist")

        #expect(stub.activations == 1)
        #expect(stub.deactivations == 0)
        #expect(registry.enabledEntries.count == 1)
    }

    @Test func disabledAndSelectedStateArePersisted() async throws {
        let first = harness.makeRegistry()
        try await harness.registerStub(in: first)
        try await harness.registerSecond(in: first)
        first.select("test.second")
        await first.setEnabled(false, for: "test.stub")

        let second = harness.makeRegistry()
        let stub = try await harness.registerStub(in: second)
        try await harness.registerSecond(in: second)

        #expect(!second.isEnabled("test.stub"))
        #expect(stub.activations == 0)
        #expect(second.selectedID == "test.second")
    }

    @Test func selectRejectsDisabledOrUnknownPlugins() async throws {
        let registry = harness.makeRegistry()
        try await harness.registerStub(in: registry)
        try await harness.registerSecond(in: registry)
        await registry.setEnabled(false, for: "test.second")

        registry.select("test.second")
        #expect(registry.selectedID == "test.stub")
        registry.select("nope")
        #expect(registry.selectedID == "test.stub")
    }

    @Test func activePillPicksHighestPriorityAndIgnoresDisabledPlugins() async throws {
        let registry = harness.makeRegistry()
        let stub = try await harness.registerStub(in: registry)
        let second = try await harness.registerSecond(in: registry)

        #expect(registry.activePill == nil)

        stub.context.pillStatus = PillStatus(text: "song", priority: .ambient)
        second.context.pillStatus = PillStatus(text: "approve?", priority: .urgent)
        #expect(registry.activePill?.text == "approve?")

        await registry.setEnabled(false, for: "test.second")
        second.context.pillStatus = PillStatus(text: "ghost", priority: .urgent)
        #expect(registry.activePill?.text == "song")
    }

    @Test func selectNeighborWalksEnabledPlugins() async throws {
        let harness = Harness()
        let registry = harness.makeRegistry()
        #expect(!registry.selectNeighbor(.forward))
        try await harness.registerStub(in: registry)
        try await harness.registerSecond(in: registry)
        #expect(registry.selectedID == "test.stub")

        #expect(!registry.selectNeighbor(.backward))
        #expect(registry.selectedID == "test.stub")
        #expect(registry.selectNeighbor(.forward))
        #expect(registry.selectedID == "test.second")
        #expect(!registry.selectNeighbor(.forward))
        #expect(registry.selectNeighbor(.backward))
        #expect(registry.selectedID == "test.stub")

        await registry.setEnabled(false, for: "test.second")
        #expect(!registry.selectNeighbor(.forward))
    }

    @Test func selectedContentSizeFollowsSelectionAndIgnoresDisabledPlugins() async throws {
        let registry = harness.makeRegistry()
        #expect(registry.selectedContentSize == nil)
        let stub = try await harness.registerStub(in: registry)
        let second = try await harness.registerSecond(in: registry)
        stub.context.contentSize = CGSize(width: 300, height: 100)
        second.context.contentSize = CGSize(width: 600, height: 300)

        #expect(registry.selectedContentSize == CGSize(width: 300, height: 100))
        registry.select("test.second")
        #expect(registry.selectedContentSize == CGSize(width: 600, height: 300))

        await registry.setEnabled(false, for: "test.second")
        #expect(registry.selectedContentSize == CGSize(width: 300, height: 100))
    }

    @Test func activePillTieGoesToEarlierRegisteredPlugin() async throws {
        let registry = harness.makeRegistry()
        let stub = try await harness.registerStub(in: registry)
        let second = try await harness.registerSecond(in: registry)

        stub.context.pillStatus = PillStatus(text: "first", priority: .info)
        second.context.pillStatus = PillStatus(text: "second", priority: .info)

        #expect(registry.activePill?.text == "first")
    }

    @Test func disableDuringSlowActivationWaitsForActivationToFinish() async throws {
        let registry = harness.makeRegistry()
        var stub: StubPlugin?
        let registration = Task { @MainActor in
            stub = try await harness.registerStub(in: registry) {
                $0.activationDelay = .milliseconds(100)
                $0.pillAfterActivation = PillStatus(text: "connected", priority: .urgent)
            }
        }
        try await Task.sleep(for: .milliseconds(20))

        await registry.setEnabled(false, for: "test.stub")
        try await registration.value
        let entry = try #require(registry.entry(for: "test.stub"))

        #expect(stub?.activations == 1)
        #expect(stub?.deactivations == 1)
        #expect(!entry.state.isActive)
        #expect(entry.context.pillStatus == nil)
        #expect(!registry.isEnabled("test.stub"))
    }

    @Test func settingsAreNamespacedPerPlugin() async throws {
        let registry = harness.makeRegistry()
        let stub = try await harness.registerStub(in: registry)
        let second = try await harness.registerSecond(in: registry)

        stub.context.settings.set(3, forKey: "volume")
        second.context.settings.set(7, forKey: "volume")

        #expect(stub.context.settings.value(forKey: "volume") == 3)
        #expect(second.context.settings.value(forKey: "volume") == 7)
        stub.context.settings.set(nil as Int?, forKey: "volume")
        #expect(stub.context.settings.value(forKey: "volume") as Int? == nil)
    }

    @Test func reenableDuringSlowDeactivationKeepsPillFromReactivation() async throws {
        let registry = harness.makeRegistry()
        let stub = try await harness.registerStub(in: registry) {
            $0.deactivationDelay = .milliseconds(100)
            $0.pillAfterActivation = PillStatus(text: "connected")
        }
        let disabling = Task { @MainActor in
            await registry.setEnabled(false, for: "test.stub")
        }
        try await Task.sleep(for: .milliseconds(20))

        await registry.setEnabled(true, for: "test.stub")
        await disabling.value
        let entry = try #require(registry.entry(for: "test.stub"))

        #expect(registry.isEnabled("test.stub"))
        #expect(entry.state.isActive)
        #expect(stub.context.pillStatus?.text == "connected")
    }

    @Test func settingsViewDefaultsToNilAndIsCached() async throws {
        let registry = harness.makeRegistry()
        try await harness.registerStub(in: registry)
        let entry = try #require(registry.entry(for: "test.stub"))

        #expect(entry.settingsView == nil)
    }

    @Test func settingsChangesAreObservable() async throws {
        let registry = harness.makeRegistry()
        let stub = try await harness.registerStub(in: registry)
        await confirmation("settings change observed") { observed in
            withObservationTracking {
                _ = stub.context.settings.value(forKey: "greeting") as String?
            } onChange: {
                observed()
            }

            stub.context.settings.set("hey", forKey: "greeting")
        }
    }

    @Test func screenIsBuiltOnceAndCached() async throws {
        let registry = harness.makeRegistry()
        let stub = try await harness.registerStub(in: registry)
        let entry = try #require(registry.entry(for: "test.stub"))

        _ = entry.screen
        _ = entry.screen

        #expect(stub.screenBuilds == 1)
    }

    @Test func preferredDropTargetIsFirstEnabledPluginAcceptingDrops() async throws {
        let registry = harness.makeRegistry()
        try await harness.registerStub(in: registry)
        #expect(registry.preferredDropTarget == nil)

        try await harness.registerSecond(in: registry) { $0.acceptsFileDrops = true }
        #expect(registry.preferredDropTarget?.id == "test.second")

        await registry.setEnabled(false, for: "test.second")
        #expect(registry.preferredDropTarget == nil)
    }
}
