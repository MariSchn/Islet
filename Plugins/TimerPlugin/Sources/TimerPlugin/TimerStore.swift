import Foundation
import IsletCore
import Observation
import os
import SwiftUI

@MainActor
@Observable
final class TimerStore {
    enum Event: Equatable {
        case ended(label: String)
        case missedEnd
    }

    struct Alert: Equatable {
        var label: String
        var until: Date
    }

    static let alertDuration: TimeInterval = 60
    static let missedEndWindow: TimeInterval = 60 * 60
    static let elapsedTint = Color.Resolved(red: 0.56, green: 0.56, blue: 0.58)
    static let remainingTint = Color.Resolved(red: 1, green: 0.62, blue: 0.04)

    private(set) var timers: [CountdownTimer] = []
    private(set) var stopwatch = Stopwatch()
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
    private let clock: @MainActor () -> Date
    private let logger: Logger
    private var isStarted = false
    private var tickTask: Task<Void, Never>?

    init(directory: URL, clock: @escaping @MainActor () -> Date = { Date() }, logger: Logger = Logger()) {
        fileURL = directory.appending(path: "timers.json")
        self.clock = clock
        self.logger = logger
        now = clock()
    }

    var pillStatus: PillStatus? {
        if let alert, now < alert.until {
            return PillStatus(text: "\(alert.label) done", systemImage: "timer", priority: .attention)
        }
        guard let timer = soonestTimer else { return nil }
        let remaining = timer.remaining(at: now)
        let ring = PillStatus.Ring(segments: [
            .init(value: max(timer.duration - remaining, 0), tint: Self.elapsedTint),
            .init(value: remaining, tint: Self.remainingTint)
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
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let loaded: [CountdownTimer]
        do {
            loaded = try JSONDecoder().decode([CountdownTimer].self, from: data)
        } catch {
            logger.error("Could not read \(self.fileURL.path, privacy: .public), keeping it aside: \(error, privacy: .public)")
            try? FileManager.default.moveItem(at: fileURL, to: fileURL.appendingPathExtension("corrupt"))
            return
        }
        let missed = loaded.filter { $0.endDate.map { $0 <= now } ?? false }
        timers = loaded.filter { !missed.contains($0) }
        guard !missed.isEmpty else { return }
        save()
        if missed.contains(where: { now.timeIntervalSince($0.endDate!) < Self.missedEndWindow }) {
            onEvent?(.missedEnd)
        }
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
        alert != nil || timers.contains(where: \.isRunning)
    }

    private var nextTickDelay: Duration? {
        guard needsTick else { return nil }
        var delay: TimeInterval = 1
        if let timer = soonestTimer {
            let remaining = timer.remaining(at: clock())
            let fraction = remaining - remaining.rounded(.down)
            delay = min(delay, fraction > 0.01 ? fraction : 1)
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
