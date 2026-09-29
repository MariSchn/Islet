import Foundation
import Observation

struct UsageWindow: Sendable, Equatable {
    var utilization: Double
    var resetsAt: Date?

    init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    static let unused = UsageWindow(utilization: 0, resetsAt: nil)

    func current(at date: Date) -> UsageWindow {
        guard let resetsAt, resetsAt <= date else { return self }
        return Self.unused
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
        ClaudeUsage(fiveHour: fiveHour?.current(at: date), sevenDay: sevenDay?.current(at: date))
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
        guard !usage.isEmpty else { return }
        let complete = ClaudeUsage(fiveHour: usage.fiveHour ?? .unused, sevenDay: usage.sevenDay ?? .unused)
        guard complete != latest else { return }
        latest = complete
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
