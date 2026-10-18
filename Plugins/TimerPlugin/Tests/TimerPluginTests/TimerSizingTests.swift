import CoreGraphics
import Foundation
import IsletCore
import Testing
@testable import TimerPlugin

@MainActor
struct TimerSizingTests {
    @Test func timersHeightGrowsWithTimersUpToFourRows() {
        let base: CGFloat = 2 * 12 + 24 + 10 + 32
        #expect(TimerPlugin.contentSize(mode: .timers, timerCount: 0) == CGSize(width: 380, height: base))
        #expect(TimerPlugin.contentSize(mode: .timers, timerCount: 1) == CGSize(width: 380, height: base + 10 + 34))
        #expect(TimerPlugin.contentSize(mode: .timers, timerCount: 2) == CGSize(width: 380, height: base + 10 + 2 * 34 + 4))
        #expect(TimerPlugin.contentSize(mode: .timers, timerCount: 4) == CGSize(width: 380, height: base + 10 + 4 * 34 + 3 * 4))
        #expect(TimerPlugin.contentSize(mode: .timers, timerCount: 5) == TimerPlugin.contentSize(mode: .timers, timerCount: 4))
        #expect(TimerPlugin.contentSize(mode: .timers, timerCount: 40) == TimerPlugin.contentSize(mode: .timers, timerCount: 4))
    }

    @Test func pomodoroAndStopwatchIgnoreTheTimerCount() {
        let header: CGFloat = 2 * 12 + 24 + 10
        #expect(TimerPlugin.contentSize(mode: .pomodoro, timerCount: 0) == CGSize(width: 380, height: header + 48 + 26 + 52 + 2 * 10))
        #expect(TimerPlugin.contentSize(mode: .pomodoro, timerCount: 3) == TimerPlugin.contentSize(mode: .pomodoro, timerCount: 0))
        #expect(TimerPlugin.contentSize(mode: .stopwatch, timerCount: 0) == CGSize(width: 380, height: header + 48 + 52 + 10))
        #expect(TimerPlugin.contentSize(mode: .stopwatch, timerCount: 3) == TimerPlugin.contentSize(mode: .stopwatch, timerCount: 0))
    }

    @Test func contentSizeFollowsTheModeAndTimers() async throws {
        let suite = "TimerSizingTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: FileManager.default.temporaryDirectory.appending(path: "\(suite)/defaults").path))
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = PluginRegistry(storageRoot: root, userDefaults: defaults)
        let entry = try await registry.register(TimerPlugin.self)
        let plugin = try #require(entry.plugin as? TimerPlugin)
        let deadline = ContinuousClock.now + .seconds(2)
        while entry.context.contentSize != TimerPlugin.contentSize(mode: .timers, timerCount: 0) {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }

        plugin.store.startTimer(minutes: 5)
        plugin.store.startTimer(minutes: 10)
        while entry.context.contentSize != TimerPlugin.contentSize(mode: .timers, timerCount: 2) {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
        plugin.store.mode = .pomodoro
        while entry.context.contentSize != TimerPlugin.contentSize(mode: .pomodoro, timerCount: 2) {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
        await registry.setEnabled(false, for: TimerPlugin.manifest.id)
    }
}
