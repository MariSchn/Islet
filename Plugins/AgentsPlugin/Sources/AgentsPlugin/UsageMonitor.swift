import Foundation
import Observation

struct UsageWindow: Sendable, Equatable {
    var utilization: Double
    var resetsAt: Date?

    init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    func isCurrent(at date: Date) -> Bool {
        resetsAt.map { $0 > date } ?? true
    }
}

struct ClaudeUsage: Sendable, Equatable {
    var fiveHour: UsageWindow?
    var sevenDay: UsageWindow?

    init(fiveHour: UsageWindow?, sevenDay: UsageWindow?) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    var isEmpty: Bool { fiveHour == nil && sevenDay == nil }

    func current(at date: Date) -> ClaudeUsage {
        ClaudeUsage(fiveHour: fiveHour.flatMap { $0.isCurrent(at: date) ? $0 : nil }, sevenDay: sevenDay.flatMap { $0.isCurrent(at: date) ? $0 : nil })
    }
}

@MainActor
@Observable
final class UsageMonitor {
    var isEnabled: Bool
    private var latest: ClaudeUsage?
    private var expiries = 0
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private let now: () -> Date

    init(isEnabled: Bool = false, now: @escaping () -> Date = Date.init) {
        self.isEnabled = isEnabled
        self.now = now
    }

    var usage: ClaudeUsage? {
        _ = expiries
        guard let current = latest?.current(at: now()), !current.isEmpty else { return nil }
        return current
    }

    func receive(_ usage: ClaudeUsage) {
        guard usage != latest else { return }
        latest = usage
        scheduleExpiry()
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        let date = now()
        guard let next = [latest?.fiveHour?.resetsAt, latest?.sevenDay?.resetsAt].compactMap({ $0 }).filter({ $0 > date }).min() else { return }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(next.timeIntervalSince(date) + 1))
            guard !Task.isCancelled, let self else { return }
            expiries += 1
            scheduleExpiry()
        }
    }
}
