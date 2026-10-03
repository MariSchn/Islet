import Foundation
import IsletCore
import Testing
@testable import TimerPlugin

@MainActor
struct TimerPluginTests {
    @Test func derivesTheRingPillFromRunningTimers() async throws {
        let suite = "TimerPluginTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        defer { try? FileManager.default.removeItem(at: root) }

        let registry = PluginRegistry(storageRoot: root, userDefaults: defaults)
        let entry = try await registry.register(TimerPlugin.self)
        let plugin = try #require(entry.plugin as? TimerPlugin)
        #expect(entry.state.isActive)
        #expect(entry.context.pillStatus == nil)

        let timer = plugin.store.startTimer(minutes: 25)
        let deadline = ContinuousClock.now + .seconds(2)
        while entry.context.pillStatus?.ring == nil {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
        #expect(entry.context.pillStatus?.priority == .ambient)
        #expect(entry.context.pillStatus?.systemImage == "timer")

        plugin.store.cancel(timer.id)
        while entry.context.pillStatus != nil {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
        await registry.setEnabled(false, for: TimerPlugin.manifest.id)
    }

    @Test func restoresTimersOnActivation() async throws {
        let suite = "TimerPluginTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: TimerPlugin.manifest.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        TimerStore(directory: directory).startTimer(minutes: 5)

        let registry = PluginRegistry(storageRoot: root, userDefaults: defaults)
        let entry = try await registry.register(TimerPlugin.self)
        let plugin = try #require(entry.plugin as? TimerPlugin)
        #expect(plugin.store.timers.map(\.label) == ["5 min"])
        await registry.setEnabled(false, for: TimerPlugin.manifest.id)
    }
}
