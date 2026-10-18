import Foundation
import IsletCore
import Testing
@testable import TimerPlugin

@MainActor
final class TimerStoreTests {
    let directory: URL
    let clock = TestClock()

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "TimerStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    isolated deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func makeStore() -> (TimerStore, Recorder) {
        let store = TimerStore(directory: directory, clock: { [clock] in clock.now })
        let recorder = Recorder()
        store.onEvent = { recorder.events.append($0) }
        return (store, recorder)
    }

    @MainActor
    final class Recorder {
        var events: [TimerStore.Event] = []
    }

    @Test func startPauseResumeAndCancel() {
        let (store, _) = makeStore()
        let timer = store.startTimer(minutes: 5)
        #expect(timer.label == "5 min")
        #expect(timer.duration == 300)
        #expect(store.timers.first?.endDate == clock.now.addingTimeInterval(300))

        clock.advance(100)
        store.pause(timer.id)
        #expect(store.timers.first?.isRunning == false)
        #expect(store.timers.first?.remaining == 200)

        clock.advance(1000)
        #expect(store.timers.first?.remaining(at: clock.now) == 200)
        store.resume(timer.id)
        #expect(store.timers.first?.endDate == clock.now.addingTimeInterval(200))
        #expect(store.timers.first?.remaining == nil)

        clock.advance(50)
        #expect(store.timers.first?.remaining(at: clock.now) == 150)
        store.cancel(timer.id)
        #expect(store.timers.isEmpty)
    }

    @Test func pausedTimersDoNotEnd() {
        let (store, recorder) = makeStore()
        let timer = store.startTimer(minutes: 1)
        clock.advance(30)
        store.pause(timer.id)
        clock.advance(600)
        store.tick()
        #expect(recorder.events.isEmpty)
        #expect(store.timers.count == 1)
    }

    @Test func endingFiresOnce() {
        let (store, recorder) = makeStore()
        store.startTimer(minutes: 1)
        clock.advance(59)
        store.tick()
        #expect(recorder.events.isEmpty)
        clock.advance(1)
        store.tick()
        store.tick()
        clock.advance(10)
        store.tick()
        #expect(recorder.events == [.ended(label: "1 min")])
        #expect(store.timers.isEmpty)
    }

    @Test func severalTimersEndInOrder() {
        let (store, recorder) = makeStore()
        store.startTimer(minutes: 10)
        store.startTimer(minutes: 1)
        store.startTimer(minutes: 5)
        clock.advance(400)
        store.tick()
        #expect(recorder.events == [.ended(label: "1 min"), .ended(label: "5 min")])
        #expect(store.timers.map(\.label) == ["10 min"])
        clock.advance(200)
        store.tick()
        #expect(recorder.events.last == .ended(label: "10 min"))
        #expect(store.timers.isEmpty)
    }

    @Test func pillShowsTheSoonestTimerAsARing() throws {
        let (store, _) = makeStore()
        #expect(store.pillStatus == nil)
        store.startTimer(minutes: 10)
        let short = store.startTimer(minutes: 5)
        clock.advance(60)
        store.tick()
        let pill = try #require(store.pillStatus)
        #expect(pill.text == "4:00")
        #expect(pill.priority == .info)
        #expect(pill.ring?.segments.map(\.value) == [60, 240])
        #expect(pill.ring?.segments.map(\.tint) == [TimerStore.elapsedTint, TimerStore.remainingTint])

        store.pause(short.id)
        #expect(store.pillStatus?.text == "9:00")
        clock.advance(0.5)
        store.tick()
        #expect(store.pillStatus?.text == "9:00")
    }

    @Test func endingShowsAnAttentionPillForAMinute() {
        let (store, _) = makeStore()
        store.startTimer(minutes: 1)
        clock.advance(60)
        store.tick()
        #expect(store.pillStatus == PillStatus(text: "1 min done", systemImage: "timer", priority: .attention))
        clock.advance(59)
        store.tick()
        #expect(store.pillStatus?.priority == .attention)
        clock.advance(1)
        store.tick()
        #expect(store.pillStatus == nil)
        #expect(store.alert == nil)
    }

    @Test func showingTheScreenDismissesTheAlert() {
        let (store, _) = makeStore()
        store.startTimer(minutes: 1)
        clock.advance(60)
        store.tick()
        #expect(store.alert != nil)
        store.isScreenVisible = true
        #expect(store.alert == nil)
        #expect(store.pillStatus == nil)
    }

    @Test func noAlertWhenTheScreenIsVisible() {
        let (store, recorder) = makeStore()
        store.isScreenVisible = true
        store.startTimer(minutes: 1)
        clock.advance(60)
        store.tick()
        #expect(recorder.events == [.ended(label: "1 min")])
        #expect(store.alert == nil)
        #expect(store.pillStatus == nil)
    }

    @Test func tickTaskEndsTimersAndStops() async throws {
        let store = TimerStore(directory: directory)
        let recorder = Recorder()
        store.onEvent = { recorder.events.append($0) }
        store.start()
        #expect(!store.isTicking)
        store.isScreenVisible = true
        store.startTimer(label: "Short", duration: 0.2)
        #expect(store.isTicking)
        let deadline = ContinuousClock.now + .seconds(5)
        while recorder.events.isEmpty || store.isTicking {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(recorder.events == [.ended(label: "Short")])
        #expect(store.timers.isEmpty)

        store.startTimer(minutes: 5)
        #expect(store.isTicking)
        store.stop()
        #expect(!store.isTicking)
    }

    @Test func persistenceRoundTrip() {
        let (store, _) = makeStore()
        store.startTimer(minutes: 5)
        let paused = store.startTimer(minutes: 25)
        clock.advance(60)
        store.pause(paused.id)
        store.startStopwatch()

        clock.advance(30)
        let (reloaded, recorder) = makeStore()
        reloaded.load()
        #expect(reloaded.timers == store.timers)
        #expect(reloaded.timers.first?.remaining(at: clock.now) == 210)
        #expect(reloaded.timers.last?.remaining(at: clock.now) == 1440)
        #expect(reloaded.stopwatch == Stopwatch())
        #expect(recorder.events.isEmpty)
    }

    @Test func recentlyMissedEndsAnnounceOnce() {
        let (store, _) = makeStore()
        store.startTimer(minutes: 1)
        store.startTimer(minutes: 5)
        store.startTimer(minutes: 25)
        clock.advance(10 * 60)
        let (reloaded, recorder) = makeStore()
        reloaded.load()
        #expect(recorder.events == [.missedEnd])
        #expect(reloaded.timers.map(\.label) == ["25 min"])

        let (again, againRecorder) = makeStore()
        again.load()
        #expect(againRecorder.events.isEmpty)
        #expect(again.timers.map(\.label) == ["25 min"])
    }

    @Test func pausedTimersSurviveAReloadPastTheirEnd() {
        let (store, _) = makeStore()
        let timer = store.startTimer(minutes: 1)
        clock.advance(20)
        store.pause(timer.id)
        clock.advance(3 * 60 * 60)
        let (reloaded, recorder) = makeStore()
        reloaded.load()
        #expect(recorder.events.isEmpty)
        #expect(reloaded.timers.first?.remaining(at: clock.now) == 40)
    }

    @Test func oldMissedEndsAreRemovedSilently() {
        let (store, _) = makeStore()
        store.startTimer(minutes: 1)
        clock.advance(2 * 60 * 60)
        let (reloaded, recorder) = makeStore()
        reloaded.load()
        #expect(recorder.events.isEmpty)
        #expect(reloaded.timers.isEmpty)
    }

    @Test func corruptFileIsKeptAside() throws {
        let file = directory.appending(path: "timers.json")
        try Data("not json".utf8).write(to: file)
        let (store, _) = makeStore()
        store.load()
        #expect(store.timers.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.appendingPathExtension("corrupt").path))
    }

    @Test func stopwatchStartStopAndReset() {
        let (store, _) = makeStore()
        store.startStopwatch()
        #expect(store.stopwatch.isRunning)
        clock.advance(12)
        #expect(store.stopwatch.elapsed(at: clock.now) == 12)
        store.stopStopwatch()
        #expect(!store.stopwatch.isRunning)
        #expect(store.stopwatch.accumulated == 12)
        clock.advance(100)
        #expect(store.stopwatch.elapsed(at: clock.now) == 12)
        store.startStopwatch()
        clock.advance(3)
        #expect(store.stopwatch.elapsed(at: clock.now) == 15)
        store.resetStopwatch()
        #expect(store.stopwatch == Stopwatch())
        #expect(store.stopwatch.elapsed(at: clock.now) == 0)
    }

    @Test func formatsRemainingTime() {
        #expect(TimerFormat.clock(0) == "0:00")
        #expect(TimerFormat.clock(59.2) == "1:00")
        #expect(TimerFormat.clock(65) == "1:05")
        #expect(TimerFormat.clock(1500) == "25:00")
        #expect(TimerFormat.countdown(1500) == "25:00")
        #expect(TimerFormat.countdown(290.4) == "4:51")
        #expect(TimerFormat.countdown(5400) == "1:30:00")
        #expect(TimerFormat.elapsed(0) == "0:00")
        #expect(TimerFormat.elapsed(59.9) == "0:59")
        #expect(TimerFormat.elapsed(3725) == "1:02:05")
    }
}
