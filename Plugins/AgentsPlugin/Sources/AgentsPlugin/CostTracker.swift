import Foundation

struct CostTracker: Codable, Equatable {
    private var lastCost: [String: Double] = [:]
    private var lastReported: [String: Date] = [:]
    private var accumulated = 0.0
    private var day: Date?
    var calendar = Calendar.current

    private enum CodingKeys: String, CodingKey {
        case lastCost, lastReported, accumulated, day
    }

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastCost = try container.decode([String: Double].self, forKey: .lastCost)
        lastReported = try container.decodeIfPresent([String: Date].self, forKey: .lastReported) ?? [:]
        accumulated = try container.decode(Double.self, forKey: .accumulated)
        day = try container.decodeIfPresent(Date.self, forKey: .day)
    }

    mutating func total(at date: Date) -> Double {
        roll(to: date)
        return accumulated
    }

    mutating func record(sessionID: String, cost: Double, at date: Date, sessionDuration: Duration? = nil) {
        roll(to: date)
        lastReported[sessionID] = date
        if lastCost[sessionID] == nil, let sessionDuration,
           date.addingTimeInterval(-TimeInterval(sessionDuration.components.seconds)) < calendar.startOfDay(for: date) {
            lastCost[sessionID] = cost
            return
        }
        let previous = lastCost[sessionID] ?? 0
        accumulated += max(cost - previous, 0)
        lastCost[sessionID] = max(previous, cost)
    }

    private mutating func roll(to date: Date) {
        let start = calendar.startOfDay(for: date)
        if let day, start != day {
            accumulated = 0
            let yesterday = calendar.date(byAdding: .day, value: -1, to: start) ?? start
            lastReported = lastReported.filter { $0.value >= yesterday }
            lastCost = lastCost.filter { lastReported[$0.key] != nil }
        }
        day = start
    }
}
