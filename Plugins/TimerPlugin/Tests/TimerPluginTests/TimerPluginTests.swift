import Foundation
import IsletCore
import Testing
@testable import TimerPlugin

@MainActor
struct TimerPluginTests {
    @Test func derivesTheRingPillFromRunningTimers() async throws {
        let suite = "TimerPluginTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: FileManager.default.temporaryDirectory.appending(path: "\(suite)/defaults").path))
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

    @Test func loadsAndSavesPomodoroSettings() async throws {
        let suite = "TimerPluginTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: FileManager.default.temporaryDirectory.appending(path: "\(suite)/defaults").path))
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        defer { try? FileManager.default.removeItem(at: root) }
        let prefix = "plugin.\(TimerPlugin.manifest.id)."
        defaults.set(50, forKey: prefix + "pomodoroWorkMinutes")
        defaults.set(true, forKey: prefix + "pomodoroStartsNextPhaseAutomatically")

        let registry = PluginRegistry(storageRoot: root, userDefaults: defaults)
        let entry = try await registry.register(TimerPlugin.self)
        let plugin = try #require(entry.plugin as? TimerPlugin)
        #expect(plugin.store.pomodoroSettings == PomodoroSettings(workMinutes: 50, startsNextPhaseAutomatically: true))
        let deadline = ContinuousClock.now + .seconds(2)
        while entry.context.contentSize == nil {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
        await Task.yield()
        #expect(defaults.object(forKey: prefix + "pomodoroShortBreakMinutes") == nil)
        #expect(defaults.object(forKey: prefix + "pomodoroLongBreakMinutes") == nil)

        plugin.store.pomodoroSettings.shortBreakMinutes = 10
        while defaults.integer(forKey: prefix + "pomodoroShortBreakMinutes") != 10 {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
        #expect(defaults.integer(forKey: prefix + "pomodoroWorkMinutes") == 50)
        await registry.setEnabled(false, for: TimerPlugin.manifest.id)
    }

    @Test func clampsStoredPomodoroDurations() async throws {
        let suite = "TimerPluginTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: FileManager.default.temporaryDirectory.appending(path: "\(suite)/defaults").path))
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        defer { try? FileManager.default.removeItem(at: root) }
        let prefix = "plugin.\(TimerPlugin.manifest.id)."
        defaults.set(0, forKey: prefix + "pomodoroWorkMinutes")
        defaults.set(500, forKey: prefix + "pomodoroLongBreakMinutes")

        let registry = PluginRegistry(storageRoot: root, userDefaults: defaults)
        let entry = try await registry.register(TimerPlugin.self)
        let plugin = try #require(entry.plugin as? TimerPlugin)
        #expect(plugin.store.pomodoroSettings == PomodoroSettings(workMinutes: 1, longBreakMinutes: 60))
        await registry.setEnabled(false, for: TimerPlugin.manifest.id)
    }

    @Test func announcesPhaseChanges() {
        let toBreak = TimerPlugin.announcement(for: .shortBreak)
        #expect(toBreak.text == "Time for a break")
        #expect(toBreak.tint == TimerStore.breakTint)
        #expect(TimerPlugin.announcement(for: .longBreak).text == "Time for a break")
        let toWork = TimerPlugin.announcement(for: .work)
        #expect(toWork.text == "Back to work")
        #expect(toWork.tint == TimerStore.workTint)
        #expect(toWork.priority == .attention)
    }

    @Test func restoresTimersOnActivation() async throws {
        let suite = "TimerPluginTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: FileManager.default.temporaryDirectory.appending(path: "\(suite)/defaults").path))
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
