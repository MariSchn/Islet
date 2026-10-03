import Foundation
import IsletCore
import Testing
@testable import TimerPlugin

@MainActor
final class PomodoroTests {
    let directory: URL
    let clock = TestClock()
    var events: [TimerStore.Event] = []

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "PomodoroTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    isolated deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func makeStore(_ settings: PomodoroSettings = PomodoroSettings()) -> TimerStore {
        let store = TimerStore(directory: directory, pomodoroSettings: settings, clock: { [clock] in clock.now })
        store.onEvent = { [unowned self] in events.append($0) }
        return store
    }

    func finishPhase(_ store: TimerStore) {
        clock.advance(store.pomodoro?.remaining(at: clock.now) ?? 0)
        store.tick()
    }

    @Test func phaseSequenceEndsInALongBreak() {
        let store = makeStore(PomodoroSettings(startsNextPhaseAutomatically: true))
        store.startPomodoro()
        var phases = [store.pomodoro?.phase]
        var dots = [store.pomodoro?.completedWorkPhases]
        for _ in 0..<8 {
            finishPhase(store)
            phases.append(store.pomodoro?.phase)
            dots.append(store.pomodoro?.completedWorkPhases)
        }
        #expect(phases == [.work, .shortBreak, .work, .shortBreak, .work, .shortBreak, .work, .longBreak, .work])
        #expect(dots == [0, 1, 1, 2, 2, 3, 3, 4, 0])
        #expect(events.prefix(2) == [.phaseEnded(next: .shortBreak), .phaseEnded(next: .work)])
        #expect(events[6] == .phaseEnded(next: .longBreak))
        #expect(events.count == 8)
    }

    @Test func automaticStartRunsTheNextPhase() {
        let store = makeStore(PomodoroSettings(startsNextPhaseAutomatically: true))
        store.startPomodoro()
        finishPhase(store)
        #expect(store.pomodoro?.phase == .shortBreak)
        #expect(store.pomodoro?.isRunning == true)
        #expect(store.pomodoro?.endDate == clock.now.addingTimeInterval(5 * 60))
    }

    @Test func manualStartWaitsForStart() {
        let store = makeStore()
        store.startPomodoro()
        finishPhase(store)
        #expect(events == [.phaseEnded(next: .shortBreak)])
        #expect(store.pomodoro?.phase == .shortBreak)
        #expect(store.pomodoro?.isRunning == false)
        clock.advance(600)
        store.tick()
        #expect(events.count == 1)
        #expect(store.pomodoro?.remaining(at: clock.now) == 300)

        store.startPomodoro()
        #expect(store.pomodoro?.endDate == clock.now.addingTimeInterval(5 * 60))
        finishPhase(store)
        #expect(events.last == .phaseEnded(next: .work))
        #expect(store.pomodoro?.phase == .work)
        #expect(store.pomodoro?.isRunning == false)
    }

    @Test func durationsComeFromSettings() {
        let store = makeStore(PomodoroSettings(workMinutes: 1, shortBreakMinutes: 2, longBreakMinutes: 3))
        store.startPomodoro()
        #expect(store.pomodoro?.duration == 60)
        #expect(store.pomodoro?.endDate == clock.now.addingTimeInterval(60))
        finishPhase(store)
        #expect(store.pomodoro?.duration == 120)

        store.pomodoroSettings.shortBreakMinutes = 4
        store.startPomodoro()
        #expect(store.pomodoro?.duration == 240)
        for _ in 0..<6 {
            finishPhase(store)
            store.startPomodoro()
        }
        #expect(store.pomodoro?.phase == .longBreak)
        #expect(store.pomodoro?.duration == 180)
    }

    @Test func pauseKeepsTheRemainingTimeAndStopResets() {
        let store = makeStore()
        store.startPomodoro()
        clock.advance(100)
        store.pausePomodoro()
        #expect(store.pomodoro?.remaining == 1400)
        store.pomodoroSettings.workMinutes = 50
        clock.advance(1000)
        store.startPomodoro()
        #expect(store.pomodoro?.endDate == clock.now.addingTimeInterval(1400))
        #expect(store.pomodoro?.duration == 1500)
        store.stopPomodoro()
        #expect(store.pomodoro == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "pomodoro.json").path))
    }

    @Test func pillIsTintedByPhaseAndWinsOverTimers() throws {
        let store = makeStore()
        store.isScreenVisible = true
        store.startTimer(minutes: 10)
        store.startPomodoro()
        clock.advance(300)
        store.tick()
        let work = try #require(store.pillStatus)
        #expect(work.text == "20:00")
        #expect(work.priority == .ambient)
        #expect(work.ring?.segments.map(\.value) == [300, 1200])
        #expect(work.ring?.segments.map(\.tint) == [TimerStore.elapsedTint, TimerStore.workTint])

        finishPhase(store)
        #expect(store.timers.isEmpty)
        #expect(store.pillStatus == nil)
        store.startPomodoro()
        #expect(store.pillStatus?.ring?.segments.last?.tint == TimerStore.breakTint)

        store.pausePomodoro()
        store.startTimer(minutes: 3)
        #expect(store.pillStatus?.ring?.segments.last?.tint == TimerStore.remainingTint)
        #expect(store.pillStatus?.text == "3:00")
    }

    @Test func timerAlertWinsOverThePomodoroPill() {
        let store = makeStore()
        store.startPomodoro()
        store.startTimer(minutes: 1)
        clock.advance(60)
        store.tick()
        #expect(store.pillStatus?.priority == .attention)
        #expect(store.pillStatus?.text == "1 min done")
    }

    @Test func persistenceRoundTrip() {
        let store = makeStore()
        store.startPomodoro()
        finishPhase(store)
        store.startPomodoro()
        clock.advance(60)
        store.pausePomodoro()

        let reloaded = makeStore()
        reloaded.load()
        #expect(reloaded.pomodoro == store.pomodoro)
        #expect(reloaded.pomodoro?.phase == .shortBreak)
        #expect(reloaded.pomodoro?.completedWorkPhases == 1)
        #expect(reloaded.pomodoro?.remaining(at: clock.now) == 240)
    }

    @Test func runningPhaseContinuesAfterAReload() {
        let store = makeStore()
        store.startPomodoro()
        clock.advance(600)
        let reloaded = makeStore()
        reloaded.load()
        #expect(reloaded.pomodoro?.isRunning == true)
        #expect(reloaded.pomodoro?.remaining(at: clock.now) == 900)
        #expect(events.isEmpty)
    }

    @Test func tickTaskEndsPhases() async throws {
        let store = makeStore()
        store.start()
        store.startPomodoro()
        #expect(store.isTicking)
        store.pausePomodoro()
        #expect(!store.isTicking)
        store.startPomodoro()
        clock.advance(1500)
        let deadline = ContinuousClock.now + .seconds(5)
        while events.isEmpty || store.isTicking {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(events == [.phaseEnded(next: .shortBreak)])
        #expect(store.pomodoro?.phase == .shortBreak)
        store.stop()
    }

    @Test func missedTimerAndPhaseAnnounceOnce() {
        let store = makeStore()
        store.startPomodoro()
        store.startTimer(minutes: 5)
        clock.advance(30 * 60)
        makeStore().load()
        #expect(events == [.missedPhaseEnd(next: .shortBreak)])
    }

    @Test func phaseThatEndedWhileNotRunningMovesOn() {
        let store = makeStore(PomodoroSettings(startsNextPhaseAutomatically: true))
        store.startPomodoro()
        clock.advance(30 * 60)
        let reloaded = makeStore(PomodoroSettings(startsNextPhaseAutomatically: true))
        reloaded.load()
        #expect(events == [.missedPhaseEnd(next: .shortBreak)])
        #expect(reloaded.pomodoro?.phase == .shortBreak)
        #expect(reloaded.pomodoro?.isRunning == false)

        events.removeAll()
        makeStore().load()
        #expect(events.isEmpty)
    }

    @Test func oldMissedPhaseEndMovesOnSilently() {
        let store = makeStore()
        store.startPomodoro()
        clock.advance(3 * 60 * 60)
        let reloaded = makeStore()
        reloaded.load()
        #expect(events.isEmpty)
        #expect(reloaded.pomodoro?.phase == .shortBreak)
    }
}
