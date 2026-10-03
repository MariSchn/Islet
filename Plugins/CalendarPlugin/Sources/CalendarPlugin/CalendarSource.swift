import Foundation
import SwiftUI

enum CalendarAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    case restricted
    case fullAccess
}

struct CalendarInfo: Sendable, Equatable, Identifiable {
    let id: String
    var title: String
    var accountID: String
    var account: String
    var color: Color.Resolved
}

struct CalendarEvent: Sendable, Equatable, Identifiable {
    let identifier: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarID: String
    var color: Color.Resolved
    var location: String?

    var id: String {
        "\(identifier)@\(start.timeIntervalSinceReferenceDate)"
    }

    func isInProgress(at now: Date) -> Bool {
        !isAllDay && start <= now && now < end
    }

    func remainingMinutes(at now: Date) -> Int {
        max(Int((end.timeIntervalSince(now) / 60).rounded(.up)), 0)
    }

    func timeLabel(at now: Date) -> String {
        if isAllDay { return "All day" }
        if isInProgress(at: now) { return "now · \(remainingMinutes(at: now)) min left" }
        return "\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
    }
}

@MainActor
protocol CalendarSource: AnyObject {
    var authorization: CalendarAuthorization { get }
    func requestAccess() async throws -> Bool
    func calendars() -> [CalendarInfo]
    func events(from start: Date, to end: Date, calendarIDs: Set<String>) -> [CalendarEvent]
    func changes() -> AsyncStream<Void>
}
