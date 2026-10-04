import Foundation

struct CostTracker: Codable, Equatable {
    private var lastCost: [String: Double] = [:]
    private var accumulated = 0.0
    private var day: Date?
    var calendar = Calendar.current

    private enum CodingKeys: String, CodingKey {
        case lastCost, accumulated, day
    }

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func keeping(sessionIDs: Set<String>) -> CostTracker {
        var tracker = self
        tracker.lastCost = lastCost.filter { sessionIDs.contains($0.key) }
        return tracker
    }

    mutating func total(at date: Date) -> Double {
        roll(to: date)
        return accumulated
    }

    mutating func record(sessionID: String, cost: Double, at date: Date) {
        roll(to: date)
        let previous = lastCost[sessionID] ?? 0
        accumulated += max(cost - previous, 0)
        lastCost[sessionID] = max(previous, cost)
    }

    private mutating func roll(to date: Date) {
        let start = calendar.startOfDay(for: date)
        if let day, start != day {
            accumulated = 0
        }
        day = start
    }
}
