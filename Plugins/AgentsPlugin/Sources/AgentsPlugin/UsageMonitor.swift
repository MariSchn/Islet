import Foundation
import Observation

struct UsageWindow: Sendable, Equatable {
    var utilization: Double
    var resetsAt: Date?

    static let unused = UsageWindow(utilization: 0, resetsAt: nil)
    static let resetTolerance: TimeInterval = 60

    func current(at date: Date) -> UsageWindow {
        guard let resetsAt, resetsAt <= date else { return self }
        return Self.unused
    }

    func merged(with newer: UsageWindow) -> UsageWindow {
        guard let current = resetsAt, let next = newer.resetsAt else { return newer }
        if next > current.addingTimeInterval(Self.resetTolerance) { return newer }
        if next < current.addingTimeInterval(-Self.resetTolerance) { return self }
        return newer.utilization >= utilization ? newer : self
    }
}

struct ClaudeUsage: Sendable, Equatable {
    var fiveHour: UsageWindow?
    var sevenDay: UsageWindow?

    var isEmpty: Bool { fiveHour == nil && sevenDay == nil }

    func current(at date: Date) -> ClaudeUsage {
        ClaudeUsage(fiveHour: fiveHour?.current(at: date), sevenDay: sevenDay?.current(at: date))
    }
}

struct AntigravityQuota: Sendable, Equatable {
    struct Bucket: Sendable, Equatable {
        var name: String
        var window: UsageWindow

        var label: String {
            let base = name.hasSuffix("-weekly") ? String(name.dropLast(7)) : name
            return base.count <= 2 ? base.uppercased() : base.prefix(1).uppercased() + base.dropFirst()
        }
    }

    var buckets: [Bucket]

    func current(at date: Date) -> AntigravityQuota {
        AntigravityQuota(buckets: buckets.map { Bucket(name: $0.name, window: $0.window.current(at: date)) })
    }
}

@MainActor
@Observable
final class UsageMonitor {
    var isEnabled: Bool
    private var latest: ClaudeUsage?
    private var latestAntigravity: AntigravityQuota?
    private var expiries = 0
    @ObservationIgnored private var costs = CostTracker()
    private var costTick = 0
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var costResetTask: Task<Void, Never>?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar

    init(isEnabled: Bool = false, now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.isEnabled = isEnabled
        self.now = now
        self.calendar = calendar
        costs = CostTracker(calendar: calendar)
    }

    var usage: ClaudeUsage? {
        _ = expiries
        guard let current = latest?.current(at: now()), !current.isEmpty else { return nil }
        return current
    }

    var antigravityQuota: AntigravityQuota? {
        _ = expiries
        guard let current = latestAntigravity?.current(at: now()), !current.buckets.isEmpty else { return nil }
        return current
    }

    func receive(_ quota: AntigravityQuota) {
        guard !quota.buckets.isEmpty, quota != latestAntigravity else { return }
        latestAntigravity = quota
        scheduleExpiry()
    }

    var dailyCost: Double {
        _ = costTick
        return costs.total(at: now())
    }

    func costs(keeping sessionIDs: Set<String>) -> CostTracker {
        costs.keeping(sessionIDs: sessionIDs)
    }

    func restore(_ costs: CostTracker) {
        self.costs = costs
        self.costs.calendar = calendar
        costTick += 1
        scheduleCostReset()
    }

    func record(sessionID: String, cost: Double) {
        costs.record(sessionID: sessionID, cost: cost, at: now())
        costTick += 1
        scheduleCostReset()
    }

    func receive(_ usage: ClaudeUsage) {
        guard !usage.isEmpty else { return }
        let merged = ClaudeUsage(fiveHour: Self.merge(latest?.fiveHour, usage.fiveHour), sevenDay: Self.merge(latest?.sevenDay, usage.sevenDay))
        guard merged != latest else { return }
        latest = merged
        scheduleExpiry()
    }

    private static func merge(_ known: UsageWindow?, _ reported: UsageWindow?) -> UsageWindow {
        switch (known, reported) {
        case let (known?, reported?): known.merged(with: reported)
        case let (known?, nil): known
        case let (nil, reported?): reported
        case (nil, nil): .unused
        }
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        let date = now()
        let resets = [latest?.fiveHour?.resetsAt, latest?.sevenDay?.resetsAt] + (latestAntigravity?.buckets ?? []).map(\.window.resetsAt)
        guard let next = resets.compactMap({ $0 }).filter({ $0 > date }).min() else { return }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(next.timeIntervalSince(date) + 1))
            guard !Task.isCancelled, let self else { return }
            expiries += 1
            scheduleExpiry()
        }
    }

    private func scheduleCostReset() {
        costResetTask?.cancel()
        let date = now()
        let start = calendar.startOfDay(for: date)
        guard let next = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        costResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(next.timeIntervalSince(date) + 1))
            guard !Task.isCancelled, let self else { return }
            costTick += 1
            scheduleCostReset()
        }
    }
}
