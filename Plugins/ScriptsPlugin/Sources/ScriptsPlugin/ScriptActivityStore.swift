import Foundation
import IsletCore
import Observation
import SwiftUI

struct ScriptActivity: Identifiable, Equatable {
    var id: String
    var text: String
    var symbol: String
    var progress: Double?
    var priority: PillStatus.Priority
    var updatedAt: Date
    var expiresAt: Date
}

@MainActor
@Observable
final class ScriptActivityStore {
    static let limit = 50
    static let progressTint = Color.Resolved(red: 0.4, green: 0.65, blue: 1)
    static let remainingTint = Color.Resolved(red: 0.56, green: 0.56, blue: 0.58)

    private(set) var activities: [ScriptActivity] = []
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    deinit {
        expiryTask?.cancel()
    }

    var newestFirst: [ScriptActivity] {
        activities.reversed()
    }

    func upsert(_ request: ScriptActivityRequest) {
        let date = now()
        activities.removeAll { $0.id == request.id }
        activities.append(ScriptActivity(id: request.id, text: request.text, symbol: ScriptSymbol.resolved(request.symbol), progress: request.progress, priority: request.priority, updatedAt: date, expiresAt: date.addingTimeInterval(request.ttl)))
        if activities.count > Self.limit {
            activities.removeFirst(activities.count - Self.limit)
        }
        scheduleExpiry()
    }

    func remove(id: String) {
        guard activities.contains(where: { $0.id == id }) else { return }
        activities.removeAll { $0.id == id }
        scheduleExpiry()
    }

    func removeAll() {
        activities = []
        scheduleExpiry()
    }

    func removeExpired() {
        let date = now()
        let remaining = activities.filter { $0.expiresAt > date }
        if remaining.count != activities.count {
            activities = remaining
        }
        scheduleExpiry()
    }

    var pillStatus: PillStatus? {
        guard let current = activities.enumerated().max(by: { ($0.element.priority, $0.offset) < ($1.element.priority, $1.offset) })?.element else { return nil }
        var ring: PillStatus.Ring?
        if let progress = current.progress {
            ring = PillStatus.Ring(segments: [
                .init(value: progress, tint: Self.progressTint),
                .init(value: 1 - progress, tint: Self.remainingTint),
            ].filter { $0.value > 0 })
        }
        return PillStatus(text: current.text, systemImage: current.symbol, priority: current.priority, ring: ring)
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        expiryTask = nil
        guard let next = activities.map(\.expiresAt).min() else { return }
        let delay = max(next.timeIntervalSince(now()), 0) + 0.1
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.removeExpired()
        }
    }
}
