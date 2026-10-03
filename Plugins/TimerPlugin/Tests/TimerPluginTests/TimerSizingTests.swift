import CoreGraphics
import Foundation
import IsletCore
import Testing
@testable import TimerPlugin

@MainActor
struct TimerSizingTests {
    @Test func heightGrowsWithTimersUpToFourRows() {
        let controls: CGFloat = 2 * 12 + 44 + 2 * 28 + 32 + 3 * 10
        #expect(TimerPlugin.contentSize(timerCount: 0) == CGSize(width: 380, height: controls))
        #expect(TimerPlugin.contentSize(timerCount: 1) == CGSize(width: 380, height: controls + 10 + 32))
        #expect(TimerPlugin.contentSize(timerCount: 2) == CGSize(width: 380, height: controls + 10 + 2 * 32 + 4))
        #expect(TimerPlugin.contentSize(timerCount: 4) == CGSize(width: 380, height: controls + 10 + 4 * 32 + 3 * 4))
        #expect(TimerPlugin.contentSize(timerCount: 5) == TimerPlugin.contentSize(timerCount: 4))
        #expect(TimerPlugin.contentSize(timerCount: 40) == TimerPlugin.contentSize(timerCount: 4))
    }

    @Test func contentSizeFollowsTheTimers() async throws {
        let suite = "TimerSizingTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = PluginRegistry(storageRoot: root, userDefaults: defaults)
        let entry = try await registry.register(TimerPlugin.self)
        let plugin = try #require(entry.plugin as? TimerPlugin)
        let deadline = ContinuousClock.now + .seconds(2)
        while entry.context.contentSize != TimerPlugin.contentSize(timerCount: 0) {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }

        plugin.store.startTimer(minutes: 5)
        plugin.store.startTimer(minutes: 10)
        while entry.context.contentSize != TimerPlugin.contentSize(timerCount: 2) {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
        await registry.setEnabled(false, for: TimerPlugin.manifest.id)
    }
}
