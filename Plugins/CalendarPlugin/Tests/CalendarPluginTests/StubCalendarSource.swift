import Foundation
@testable import CalendarPlugin

@MainActor
final class StubCalendarSource: CalendarSource {
    var authorization: CalendarAuthorization
    var grantsAccess = true
    var calendarList: [CalendarInfo]
    var eventList: [CalendarEvent]
    private(set) var accessRequests = 0
    private var continuations: [AsyncStream<Void>.Continuation] = []

    init(authorization: CalendarAuthorization = .fullAccess, calendars: [CalendarInfo] = [], events: [CalendarEvent] = []) {
        self.authorization = authorization
        calendarList = calendars
        eventList = events
    }

    func requestAccess() async throws -> Bool {
        accessRequests += 1
        authorization = grantsAccess ? .fullAccess : .denied
        return grantsAccess
    }

    func calendars() -> [CalendarInfo] {
        calendarList
    }

    func events(from start: Date, to end: Date, calendarIDs: Set<String>) -> [CalendarEvent] {
        eventList.filter { calendarIDs.contains($0.calendarID) && $0.end > start && $0.start < end }
    }

    func changes() -> AsyncStream<Void> {
        AsyncStream { continuations.append($0) }
    }

    func notifyChange() {
        continuations.forEach { $0.yield() }
    }
}
