import Foundation
import Testing
@testable import CalendarPlugin

struct CalendarEventTests {
    @Test func showsJoinFromFifteenMinutesBeforeTheStartUntilTheEnd() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var event = CalendarEvent(identifier: "a", title: "Sync", start: start, end: start.addingTimeInterval(1800), isAllDay: false, calendarID: "c", color: .init(red: 0, green: 0, blue: 0), location: nil, meetingURL: URL(string: "https://zoom.us/j/1"))
        #expect(!event.showsJoin(at: start.addingTimeInterval(-16 * 60)))
        #expect(event.showsJoin(at: start.addingTimeInterval(-15 * 60)))
        #expect(event.showsJoin(at: start.addingTimeInterval(600)))
        #expect(!event.showsJoin(at: start.addingTimeInterval(1800)))
        #expect(event.showsJoin(at: start.addingTimeInterval(1799)))
        event.isAllDay = true
        #expect(!event.showsJoin(at: start.addingTimeInterval(600)))
        event.isAllDay = false
        event.meetingURL = nil
        #expect(!event.showsJoin(at: start))
    }
}
