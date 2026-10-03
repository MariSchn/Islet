import Foundation

struct CountdownTimer: Codable, Identifiable, Equatable {
    let id: UUID
    var label: String
    var duration: TimeInterval
    var endDate: Date?
    var remaining: TimeInterval?

    init(id: UUID = UUID(), label: String, duration: TimeInterval, endDate: Date? = nil, remaining: TimeInterval? = nil) {
        self.id = id
        self.label = label
        self.duration = duration
        self.endDate = endDate
        self.remaining = remaining
    }

    var isRunning: Bool {
        endDate != nil
    }

    func remaining(at now: Date) -> TimeInterval {
        if let endDate {
            return max(endDate.timeIntervalSince(now), 0)
        }
        return remaining ?? duration
    }
}

struct Stopwatch: Equatable {
    var startDate: Date?
    var accumulated: TimeInterval = 0

    var isRunning: Bool {
        startDate != nil
    }

    func elapsed(at now: Date) -> TimeInterval {
        accumulated + (startDate.map { max(now.timeIntervalSince($0), 0) } ?? 0)
    }
}

enum TimerFormat {
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded(.up)), 0)
        let secondsPart = total % 60
        return "\(total / 60):" + (secondsPart < 10 ? "0" : "") + "\(secondsPart)"
    }
}
