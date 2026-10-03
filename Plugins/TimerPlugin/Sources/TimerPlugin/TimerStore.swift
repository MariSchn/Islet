import Foundation
import IsletCore
import Observation
import os
import SwiftUI

enum TimerMode: String, CaseIterable, Identifiable {
    case timers = "Timers"
    case pomodoro = "Pomodoro"
    case stopwatch = "Stopwatch"

    var id: String { rawValue }
}

@MainActor
@Observable
final class TimerStore {
    enum Event: Equatable {
        case ended(label: String)
        case missedEnd
        case phaseEnded(next: PomodoroPhase)
        case missedPhaseEnd(next: PomodoroPhase)
    }

    struct Alert: Equatable {
        var label: String
        var until: Date
    }

    static let alertDuration: TimeInterval = 60
    static let missedEndWindow: TimeInterval = 60 * 60
    static let elapsedTint = Color.Resolved(red: 0.56, green: 0.56, blue: 0.58)
    static let remainingTint = Color.Resolved(red: 1, green: 0.62, blue: 0.04)
    static let workTint = Color.Resolved(red: 1, green: 0.27, blue: 0.23)
    static let breakTint = Color.Resolved(red: 0.2, green: 0.78, blue: 0.35)

    var mode = TimerMode.timers
    private(set) var timers: [CountdownTimer] = []
    private(set) var stopwatch = Stopwatch()
    private(set) var pomodoro: PomodoroState?
    var pomodoroSettings: PomodoroSettings
    private(set) var alert: Alert?
    private(set) var now: Date
    var isScreenVisible = false {
        didSet {
            if isScreenVisible {
                dismissAlert()
            }
        }
    }

    @ObservationIgnored var onEvent: (@MainActor (Event) -> Void)?

    private let fileURL: URL
    private let pomodoroURL: URL
    private let clock: @MainActor () -> Date
    private let logger: Logger
    private var isStarted = false
    private var tickTask: Task<Void, Never>?

    init(directory: URL, pomodoroSettings: PomodoroSettings = PomodoroSettings(), clock: @escaping @MainActor () -> Date = { Date() }, logger: Logger = Logger()) {
        fileURL = directory.appending(path: "timers.json")
        pomodoroURL = directory.appending(path: "pomodoro.json")
        self.pomodoroSettings = pomodoroSettings
        self.clock = clock
        self.logger = logger
        now = clock()
    }

    var pillStatus: PillStatus? {
        if let alert, now < alert.until {
            return PillStatus(text: "\(alert.label) done", systemImage: "timer", priority: .attention)
        }
        if let pomodoro, pomodoro.isRunning {
            return Self.ringPill(duration: pomodoro.duration, remaining: pomodoro.remaining(at: now), tint: pomodoro.phase.isBreak ? Self.breakTint : Self.workTint)
        }
        guard let timer = soonestTimer else { return nil }
        return Self.ringPill(duration: timer.duration, remaining: timer.remaining(at: now), tint: Self.remainingTint)
    }

    private static func ringPill(duration: TimeInterval, remaining: TimeInterval, tint: Color.Resolved) -> PillStatus {
        let ring = PillStatus.Ring(segments: [
            .init(value: max(duration - remaining, 0), tint: elapsedTint),
            .init(value: remaining, tint: tint)
        ])
        return PillStatus(text: TimerFormat.clock(remaining), systemImage: "timer", priority: .ambient, ring: ring)
    }

    var soonestTimer: CountdownTimer? {
        timers.filter(\.isRunning).min { $0.endDate! < $1.endDate! }
    }

    func start() {
        isStarted = true
        load()
        updateTicking()
    }

    func stop() {
        isStarted = false
        updateTicking()
    }

    func load() {
        now = clock()
        let missedPhase = loadPomodoro()
        let missedTimer = loadTimers()
        if let missedPhase {
            onEvent?(.missedPhaseEnd(next: missedPhase))
        } else if missedTimer {
            onEvent?(.missedEnd)
        }
    }

    private func loadTimers() -> Bool {
        guard let data = try? Data(contentsOf: fileURL) else { return false }
        let loaded: [CountdownTimer]
        do {
            loaded = try JSONDecoder().decode([CountdownTimer].self, from: data)
        } catch {
            logger.error("Could not read \(self.fileURL.path, privacy: .public), keeping it aside: \(error, privacy: .public)")
            try? FileManager.default.moveItem(at: fileURL, to: fileURL.appendingPathExtension("corrupt"))
            return false
        }
        let missed = loaded.filter { $0.endDate.map { $0 <= now } ?? false }
        timers = loaded.filter { !missed.contains($0) }
        guard !missed.isEmpty else { return false }
        save()
        return missed.contains { now.timeIntervalSince($0.endDate!) < Self.missedEndWindow }
    }

    private func loadPomodoro() -> PomodoroPhase? {
        guard let data = try? Data(contentsOf: pomodoroURL) else { return nil }
        let loaded: PomodoroState
        do {
            loaded = try JSONDecoder().decode(PomodoroState.self, from: data)
        } catch {
            logger.error("Could not read \(self.pomodoroURL.path, privacy: .public), keeping it aside: \(error, privacy: .public)")
            try? FileManager.default.moveItem(at: pomodoroURL, to: pomodoroURL.appendingPathExtension("corrupt"))
            return nil
        }
        guard let endDate = loaded.endDate, endDate <= now else {
            pomodoro = loaded
            return nil
        }
        let next = loaded.next(settings: pomodoroSettings)
        pomodoro = next
        savePomodoro()
        return now.timeIntervalSince(endDate) < Self.missedEndWindow ? next.phase : nil
    }

    func startPomodoro() {
        now = clock()
        if var state = pomodoro {
            guard !state.isRunning else { return }
            if state.remaining == nil {
                state.duration = pomodoroSettings.duration(for: state.phase)
            }
            state.endDate = now.addingTimeInterval(state.remaining(at: now))
            state.remaining = nil
            pomodoro = state
        } else {
            let duration = pomodoroSettings.duration(for: .work)
            pomodoro = PomodoroState(phase: .work, completedWorkPhases: 0, duration: duration, endDate: now.addingTimeInterval(duration))
        }
        pomodoroChanged()
    }

    func pausePomodoro() {
        now = clock()
        guard var state = pomodoro, state.isRunning else { return }
        state.remaining = state.remaining(at: now)
        state.endDate = nil
        pomodoro = state
        pomodoroChanged()
    }

    func stopPomodoro() {
        guard pomodoro != nil else { return }
        pomodoro = nil
        pomodoroChanged()
    }

    @discardableResult
    func startTimer(minutes: Int) -> CountdownTimer {
        startTimer(label: "\(minutes) min", duration: TimeInterval(minutes) * 60)
    }

    @discardableResult
    func startTimer(label: String, duration: TimeInterval) -> CountdownTimer {
        now = clock()
        let timer = CountdownTimer(label: label, duration: duration, endDate: now.addingTimeInterval(duration))
        timers.append(timer)
        changed()
        return timer
    }

    func pause(_ id: CountdownTimer.ID) {
        now = clock()
        guard let index = timers.firstIndex(where: { $0.id == id }), timers[index].isRunning else { return }
        timers[index].remaining = timers[index].remaining(at: now)
        timers[index].endDate = nil
        changed()
    }

    func resume(_ id: CountdownTimer.ID) {
        now = clock()
        guard let index = timers.firstIndex(where: { $0.id == id }), !timers[index].isRunning else { return }
        timers[index].endDate = now.addingTimeInterval(timers[index].remaining(at: now))
        timers[index].remaining = nil
        changed()
    }

    func cancel(_ id: CountdownTimer.ID) {
        guard timers.contains(where: { $0.id == id }) else { return }
        timers.removeAll { $0.id == id }
        changed()
    }

    func startStopwatch() {
        guard !stopwatch.isRunning else { return }
        stopwatch.startDate = clock()
    }

    func stopStopwatch() {
        guard let startDate = stopwatch.startDate else { return }
        stopwatch.accumulated += max(clock().timeIntervalSince(startDate), 0)
        stopwatch.startDate = nil
    }

    func resetStopwatch() {
        stopwatch = Stopwatch()
    }

    func dismissAlert() {
        guard alert != nil else { return }
        alert = nil
        updateTicking()
    }

    func tick() {
        now = clock()
        if let alert, now >= alert.until {
            self.alert = nil
        }
        if let state = pomodoro, let endDate = state.endDate, endDate <= now {
            var next = state.next(settings: pomodoroSettings)
            if pomodoroSettings.startsNextPhaseAutomatically {
                next.endDate = now.addingTimeInterval(next.duration)
            }
            pomodoro = next
            savePomodoro()
            onEvent?(.phaseEnded(next: next.phase))
        }
        let ended = timers
            .filter { $0.endDate.map { $0 <= now } ?? false }
            .sorted { $0.endDate! < $1.endDate! }
        if !ended.isEmpty {
            timers.removeAll { timer in ended.contains { $0.id == timer.id } }
            save()
            for timer in ended {
                if !isScreenVisible {
                    alert = Alert(label: timer.label, until: now.addingTimeInterval(Self.alertDuration))
                }
                onEvent?(.ended(label: timer.label))
            }
        }
        updateTicking()
    }

    var isTicking: Bool {
        tickTask != nil
    }

    private var needsTick: Bool {
        alert != nil || timers.contains(where: \.isRunning) || pomodoro?.isRunning == true
    }

    private var nextTickDelay: Duration? {
        guard needsTick else { return nil }
        var delay: TimeInterval = 1
        let current = clock()
        let pomodoroRemaining = pomodoro.flatMap { $0.isRunning ? $0.remaining(at: current) : nil }
        if let remaining = pomodoroRemaining ?? soonestTimer?.remaining(at: current) {
            let fraction = remaining - remaining.rounded(.down)
            delay = min(delay, fraction > 0.01 ? fraction : 1)
        }
        if pomodoroRemaining != nil, let timerRemaining = soonestTimer?.remaining(at: current) {
            delay = min(delay, max(timerRemaining, 0))
        }
        if let alert {
            delay = min(delay, alert.until.timeIntervalSince(clock()))
        }
        return .seconds(max(delay, 0.05))
    }

    private func changed() {
        save()
        updateTicking()
    }

    private func pomodoroChanged() {
        savePomodoro()
        updateTicking()
    }

    private func savePomodoro() {
        do {
            if let pomodoro {
                try JSONEncoder().encode(pomodoro).write(to: pomodoroURL, options: .atomic)
            } else if FileManager.default.fileExists(atPath: pomodoroURL.path) {
                try FileManager.default.removeItem(at: pomodoroURL)
            }
        } catch {
            logger.error("Failed to save the Pomodoro state: \(error, privacy: .public)")
        }
    }

    private func updateTicking() {
        guard isStarted, needsTick else {
            tickTask?.cancel()
            tickTask = nil
            return
        }
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = self?.nextTickDelay else {
                    self?.tickTask = nil
                    return
                }
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(timers)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save: \(error, privacy: .public)")
        }
    }
}
