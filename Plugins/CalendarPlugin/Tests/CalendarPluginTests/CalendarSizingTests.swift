import Foundation
import Testing
@testable import CalendarPlugin

@MainActor
struct CalendarSizingTests {
    @Test func emptyAgendaUsesTheEmptyHeight() {
        let size = CalendarPlugin.contentSize(sectionCount: 0, rowCount: 0, hasMoreLine: false)
        #expect(size == CGSize(width: 420, height: CalendarPlugin.emptyContentHeight))
    }

    @Test func oneSectionWithRows() {
        let size = CalendarPlugin.contentSize(sectionCount: 1, rowCount: 3, hasMoreLine: false)
        #expect(size == CGSize(width: 420, height: 2 * 12 + 18 + 3 * 34))
    }

    @Test func twoSectionsAreSeparated() {
        let size = CalendarPlugin.contentSize(sectionCount: 2, rowCount: 4, hasMoreLine: false)
        #expect(size.height == 2 * 12 + 2 * 18 + CalendarPlugin.sectionSpacing + 4 * 34)
    }

    @Test func moreLineAddsItsHeight() {
        let without = CalendarPlugin.contentSize(sectionCount: 2, rowCount: 6, hasMoreLine: false)
        let with = CalendarPlugin.contentSize(sectionCount: 2, rowCount: 6, hasMoreLine: true)
        #expect(with.height - without.height == CalendarPlugin.moreLineHeight)
        #expect(with.width == 420)
    }

    @Test func sizeFollowsTheAgenda() {
        let event = CalendarEvent(identifier: "a", title: "A", start: .now, end: .now.addingTimeInterval(3600), isAllDay: false, calendarID: "c", color: .init(red: 0, green: 0, blue: 0), location: nil)
        let agenda = CalendarAgenda(sections: [.init(day: .today, events: [event])], moreCount: 2)
        #expect(CalendarPlugin.contentSize(for: agenda) == CalendarPlugin.contentSize(sectionCount: 1, rowCount: 1, hasMoreLine: true))
        #expect(CalendarPlugin.contentSize(for: .empty) == CalendarPlugin.contentSize(sectionCount: 0, rowCount: 0, hasMoreLine: false))
    }
}
