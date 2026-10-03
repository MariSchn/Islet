import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers
import IsletCore
import IsletTestSupport

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

    @Test func registersAPluginTypeByItsManifest() async throws {
        let registry = harness.makeRegistry()

        let entry = try await registry.register(StubPlugin.self)

        #expect(entry.id == StubPlugin.manifest.id)
        #expect(entry.plugin is StubPlugin)
        #expect(entry.state.isActive)
    }

    @Test func deactivateAllStopsEveryActivePlugin() async throws {
        let registry = harness.makeRegistry()
        let first = try await harness.registerStub(in: registry)
        let second = try await harness.registerSecond(in: registry)
        await registry.setEnabled(false, for: secondManifest.id)

        await registry.deactivateAll()

        #expect(first.deactivations == 1)
        #expect(second.deactivations == 1)
        #expect(registry.entries.allSatisfy { !$0.state.isActive })
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

        #expect(registry.activePill(.mostImportant) == nil)

        stub.context.pillStatus = PillStatus(text: "song", priority: .ambient)
        second.context.pillStatus = PillStatus(text: "approve?", priority: .urgent)
        #expect(registry.activePill(.mostImportant)?.text == "approve?")

        await registry.setEnabled(false, for: "test.second")
        second.context.pillStatus = PillStatus(text: "ghost", priority: .urgent)
        #expect(registry.activePill(.mostImportant)?.text == "song")
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

        #expect(registry.activePill(.mostImportant)?.text == "first")
    }

    @Test func lastViewedShowsSelectedPluginAndFallsBackToMostImportant() async throws {
        let registry = harness.makeRegistry()
        let stub = try await harness.registerStub(in: registry)
        let second = try await harness.registerSecond(in: registry)

        stub.context.pillStatus = PillStatus(text: "song", priority: .ambient)
        second.context.pillStatus = PillStatus(text: "working", priority: .info)
        #expect(registry.activePill(.lastViewed)?.text == "song")

        registry.select("test.second")
        #expect(registry.activePill(.lastViewed)?.text == "working")

        second.context.pillStatus = nil
        #expect(registry.activePill(.lastViewed)?.text == "song")
    }

    @Test func lastViewedKeepsTheHeldPluginWhileItHasAPill() async throws {
        let registry = harness.makeRegistry()
        let stub = try await harness.registerStub(in: registry)
        let second = try await harness.registerSecond(in: registry)
        registry.select("test.second")

        stub.context.pillStatus = PillStatus(text: "song", priority: .ambient)
        #expect(registry.pillHolder(.lastViewed) == "test.stub")

        second.context.pillStatus = PillStatus(text: "working", priority: .info)
        #expect(registry.activePill(.lastViewed, keeping: "test.stub")?.text == "song")
        #expect(registry.pillHolder(.lastViewed, keeping: "test.stub") == "test.stub")

        second.context.pillStatus = PillStatus(text: "approve?", priority: .attention)
        #expect(registry.activePill(.lastViewed, keeping: "test.stub")?.text == "approve?")
        #expect(registry.pillHolder(.lastViewed, keeping: "test.stub") == "test.stub")

        stub.context.pillStatus = nil
        #expect(registry.pillHolder(.lastViewed, keeping: "test.stub") == "test.second")
    }

    @Test func latestActivityFollowsNewestPillOrRaisedPriority() async throws {
        let registry = harness.makeRegistry()
        let stub = try await harness.registerStub(in: registry)
        let second = try await harness.registerSecond(in: registry)

        second.context.pillStatus = PillStatus(text: "finished", priority: .ambient)
        stub.context.pillStatus = PillStatus(text: "song", priority: .ambient)
        #expect(registry.activePill(.latestActivity)?.text == "song")

        second.context.pillStatus = PillStatus(text: "finished again", priority: .ambient)
        #expect(registry.activePill(.latestActivity)?.text == "song")

        second.context.pillStatus = PillStatus(text: "working", priority: .info)
        #expect(registry.activePill(.latestActivity)?.text == "working")

        stub.context.pillStatus = PillStatus(text: "next song", priority: .ambient)
        #expect(registry.activePill(.latestActivity)?.text == "working")

        stub.context.pillStatus = nil
        stub.context.pillStatus = PillStatus(text: "resumed", priority: .ambient)
        #expect(registry.activePill(.latestActivity)?.text == "resumed")
    }

    @Test func pillsThatNeedTheUserWinInEveryMode() async throws {
        let registry = harness.makeRegistry()
        let stub = try await harness.registerStub(in: registry)
        let second = try await harness.registerSecond(in: registry)

        second.context.pillStatus = PillStatus(text: "approve?", priority: .attention)
        stub.context.pillStatus = PillStatus(text: "song", priority: .ambient)

        for selection in PillSelection.allCases {
            #expect(registry.activePill(selection)?.text == "approve?")
        }
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

    @Test func rapidTogglesDuringATransitionRunInOrderAndEndDisabled() async throws {
        let registry = harness.makeRegistry()
        let stub = try await harness.registerStub(in: registry) {
            $0.deactivationDelay = .milliseconds(100)
        }
        stub.activationDelay = .milliseconds(50)
        stub.pillAfterActivation = PillStatus(text: "connected")
        let disabling = Task { @MainActor in
            await registry.setEnabled(false, for: "test.stub")
        }
        try await Task.sleep(for: .milliseconds(20))
        let enabling = Task { @MainActor in
            await registry.setEnabled(true, for: "test.stub")
        }
        let disablingAgain = Task { @MainActor in
            await registry.setEnabled(false, for: "test.stub")
        }
        await disabling.value
        await enabling.value
        await disablingAgain.value
        let entry = try #require(registry.entry(for: "test.stub"))

        #expect(!registry.isEnabled("test.stub"))
        #expect(!entry.state.isActive)
        #expect(stub.activations == 2)
        #expect(stub.deactivations == 2)
        #expect(stub.context.pillStatus == nil)
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

    @Test func dropTargetIsFirstEnabledPluginAcceptingADraggedType() async throws {
        let registry = harness.makeRegistry()
        try await harness.registerStub(in: registry)
        #expect(registry.dropTarget(for: [.fileURL]) == nil)

        try await harness.registerSecond(in: registry) { $0.acceptedDropTypes = [.fileURL] }
        #expect(registry.dropTarget(for: [.fileURL])?.id == "test.second")
        #expect(registry.dropTarget(for: []) == nil)

        await registry.setEnabled(false, for: "test.second")
        #expect(registry.dropTarget(for: [.fileURL]) == nil)
    }

    @Test func dropTargetMatchesByConformance() async throws {
        let registry = harness.makeRegistry()
        try await harness.registerStub(in: registry)
        try await harness.registerSecond(in: registry) { $0.acceptedDropTypes = [.image] }
        #expect(registry.dropTarget(for: [.png])?.id == "test.second")
        #expect(registry.dropTarget(for: [.plainText, .png])?.id == "test.second")
        #expect(registry.dropTarget(for: [.plainText]) == nil)

        let other = harness.makeRegistry()
        try await harness.registerStub(in: other)
        try await harness.registerSecond(in: other) { $0.acceptedDropTypes = [.plainText] }
        #expect(other.dropTarget(for: [.fileURL]) == nil)
    }

    private let thirdManifest = PluginManifest(id: "test.third", displayName: "Third", systemImage: "triangle")

    @discardableResult
    private func registerThird(in registry: PluginRegistry, configure: (StubPlugin) -> Void = { _ in }) async throws -> StubPlugin {
        var created: StubPlugin?
        try await registry.register(manifest: thirdManifest) { context in
            let plugin = StubPlugin(context: context)
            configure(plugin)
            created = plugin
            return plugin
        }
        return try #require(created)
    }

    private func registerThree(in registry: PluginRegistry) async throws {
        try await harness.registerStub(in: registry)
        try await harness.registerSecond(in: registry)
        try await registerThird(in: registry)
    }

    @Test func defaultOrderIsRegistrationOrder() async throws {
        let registry = harness.makeRegistry()
        try await registerThree(in: registry)

        #expect(registry.orderedEntries.map(\.id) == ["test.stub", "test.second", "test.third"])
        #expect(registry.enabledEntries.map(\.id) == ["test.stub", "test.second", "test.third"])
    }

    @Test func moveReordersEntriesAndIsRestoredByANewRegistry() async throws {
        let first = harness.makeRegistry()
        try await registerThree(in: first)
        await first.setEnabled(false, for: "test.second")

        first.move("test.third", by: -2)
        #expect(first.orderedEntries.map(\.id) == ["test.third", "test.stub", "test.second"])
        #expect(first.enabledEntries.map(\.id) == ["test.third", "test.stub"])

        first.move("test.stub", by: 10)
        #expect(first.orderedEntries.map(\.id) == ["test.third", "test.second", "test.stub"])
        first.move("test.third", by: -1)
        first.move("unknown.plugin", by: 1)
        #expect(first.orderedEntries.map(\.id) == ["test.third", "test.second", "test.stub"])

        let second = harness.makeRegistry()
        try await registerThree(in: second)
        #expect(second.orderedEntries.map(\.id) == ["test.third", "test.second", "test.stub"])
        #expect(second.enabledEntries.map(\.id) == ["test.third", "test.stub"])
    }

    @Test func unknownStoredIDsAreIgnoredAndLaterPluginsAreAppended() async throws {
        harness.defaults.set(["gone.plugin", "test.second", "test.stub"], forKey: "islet.pluginOrder")
        let registry = harness.makeRegistry()
        try await harness.registerStub(in: registry)
        try await registerThird(in: registry)
        #expect(registry.orderedEntries.map(\.id) == ["test.stub", "test.third"])

        try await harness.registerSecond(in: registry)
        #expect(registry.orderedEntries.map(\.id) == ["test.second", "test.stub", "test.third"])

        let plain = Harness()
        let later = plain.makeRegistry()
        try await plain.registerStub(in: later)
        try await plain.registerSecond(in: later)
        later.move("test.second", by: -1)
        try await registerThird(in: later)
        #expect(later.orderedEntries.map(\.id) == ["test.second", "test.stub", "test.third"])
    }

    @Test func neighborsAndDropTargetFollowTheOrder() async throws {
        let registry = harness.makeRegistry()
        try await harness.registerStub(in: registry)
        try await harness.registerSecond(in: registry) { $0.acceptedDropTypes = [.fileURL] }
        try await registerThird(in: registry) { $0.acceptedDropTypes = [.fileURL] }
        #expect(registry.dropTarget(for: [.fileURL])?.id == "test.second")

        registry.move("test.third", by: -2)
        #expect(registry.dropTarget(for: [.fileURL])?.id == "test.third")

        registry.select("test.third")
        #expect(!registry.selectNeighbor(.backward))
        #expect(registry.selectNeighbor(.forward))
        #expect(registry.selectedID == "test.stub")
        #expect(registry.selectNeighbor(.forward))
        #expect(registry.selectedID == "test.second")
        #expect(!registry.selectNeighbor(.forward))
    }
}
