import Foundation
import IsletCore
import SwiftUI
import Testing
@testable import CalendarPlugin

@MainActor
private final class TestClock {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

@MainActor
struct CalendarPillTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()
    static let blue = Color.Resolved(red: 0.2, green: 0.4, blue: 1)
    static let work = CalendarInfo(id: "work", title: "Work", accountID: "icloud", account: "iCloud", color: blue)

    static func date(_ hour: Int, _ minute: Int, _ second: Int = 0, day: Int = 3) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
    }

    static func event(_ title: String, from start: Date, minutes: Int = 30, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(identifier: title, title: title, start: start, end: start.addingTimeInterval(TimeInterval(minutes * 60)), isAllDay: allDay, calendarID: work.id, color: blue, location: nil)
    }

    fileprivate static func makeController(_ source: StubCalendarSource, clock: TestClock, includesAllDay: Bool = false, leadMinutes: Int = 10, showsPill: Bool = true) -> CalendarController {
        let controller = CalendarController(source: source, includesAllDay: includesAllDay, leadMinutes: leadMinutes, showsPill: showsPill, now: { clock.now }, calendar: calendar)
        controller.reload()
        return controller
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
    }

    @Test func noPillBeforeTheLeadTime() {
        let clock = TestClock(Self.date(9, 49))
        let source = StubCalendarSource(calendars: [Self.work], events: [Self.event("Standup", from: Self.date(10, 0))])
        let controller = Self.makeController(source, clock: clock)
        #expect(controller.pillStatus == nil)
    }

    @Test func infoPillFromTheLeadTimeWithTheRemainingMinutes() {
        let clock = TestClock(Self.date(9, 50))
        let source = StubCalendarSource(calendars: [Self.work], events: [Self.event("Standup", from: Self.date(10, 0))])
        let controller = Self.makeController(source, clock: clock)
        #expect(controller.pillStatus == PillStatus(text: "Standup in 10 min", systemImage: "calendar", priority: .info, tint: Self.blue))

        clock.now = Self.date(9, 52, 30)
        #expect(controller.pillStatus?.text == "Standup in 8 min")
        clock.now = Self.date(9, 59, 30)
        #expect(controller.pillStatus?.text == "Standup in 1 min")
    }

    @Test func leadTimeSettingMovesTheStart() {
        let clock = TestClock(Self.date(9, 40))
        let source = StubCalendarSource(calendars: [Self.work], events: [Self.event("Standup", from: Self.date(10, 0))])
        let controller = Self.makeController(source, clock: clock, leadMinutes: 15)
        #expect(controller.pillStatus == nil)
        controller.leadMinutes = 30
        #expect(controller.pillStatus?.text == "Standup in 20 min")
    }

    @Test func attentionPillForFiveMinutesFromTheStart() {
        let clock = TestClock(Self.date(10, 0))
        let source = StubCalendarSource(calendars: [Self.work], events: [
            Self.event("Standup", from: Self.date(10, 0), minutes: 2),
            Self.event("Review", from: Self.date(10, 30)),
        ])
        let controller = Self.makeController(source, clock: clock)
        #expect(controller.pillStatus == PillStatus(text: "Standup now", systemImage: "calendar", priority: .attention, tint: Self.blue))

        clock.now = Self.date(10, 4, 59)
        controller.reload()
        #expect(controller.pillStatus?.text == "Standup now")
        #expect(controller.agenda.sections.first?.events.map(\.title) == ["Review"])

        clock.now = Self.date(10, 5)
        #expect(controller.pillStatus == nil)
        clock.now = Self.date(10, 20)
        #expect(controller.pillStatus?.text == "Review in 10 min")
    }

    @Test func allDayEventsNeverProduceAPill() {
        let clock = TestClock(Self.date(23, 55))
        let source = StubCalendarSource(calendars: [Self.work], events: [
            Self.event("Holiday", from: Self.date(0, 0, day: 4), minutes: 24 * 60, allDay: true),
        ])
        let controller = Self.makeController(source, clock: clock, includesAllDay: true)
        controller.start()
        defer { controller.stop() }
        #expect(controller.events.count == 1)
        #expect(controller.pillStatus == nil)
        clock.now = Self.date(0, 1, day: 4)
        #expect(controller.pillStatus == nil)
        #expect(controller.announcementCandidate == nil)
    }

    @Test func settingOffMeansNoPill() {
        let clock = TestClock(Self.date(10, 0))
        let source = StubCalendarSource(calendars: [Self.work], events: [Self.event("Standup", from: Self.date(10, 0))])
        let controller = Self.makeController(source, clock: clock, showsPill: false)
        controller.start()
        defer { controller.stop() }
        #expect(controller.pillStatus == nil)
        clock.now = Self.date(9, 55)
        #expect(controller.pillStatus == nil)
        #expect(controller.takeAnnouncement() == nil)
        controller.showsPill = true
        #expect(controller.pillStatus?.text == "Standup in 5 min")
    }

    @Test func announcesOncePerEventAndAgainAfterItMoves() throws {
        let clock = TestClock(Self.date(9, 45))
        let source = StubCalendarSource(calendars: [Self.work], events: [Self.event("Standup", from: Self.date(10, 0))])
        let controller = Self.makeController(source, clock: clock)
        #expect(controller.announcementCandidate == nil)
        clock.now = Self.date(9, 50)
        #expect(controller.takeAnnouncement() == nil)
        controller.start()
        defer { controller.stop() }
        clock.now = Self.date(9, 45)
        #expect(controller.takeAnnouncement() == nil)

        clock.now = Self.date(9, 50)
        let announcement = try #require(controller.takeAnnouncement())
        #expect(announcement.text == "Standup in 10 min")
        #expect(announcement.systemImage == "calendar")
        #expect(announcement.priority == .info)
        #expect(controller.takeAnnouncement() == nil)

        clock.now = Self.date(9, 52)
        #expect(controller.takeAnnouncement() == nil)

        source.eventList = [Self.event("Standup", from: Self.date(9, 58))]
        controller.reload()
        #expect(controller.takeAnnouncement()?.text == "Standup in 6 min")
        #expect(controller.takeAnnouncement() == nil)
    }

    @Test func announcesAnEventThatStartsWhileAnotherIsStarting() throws {
        let clock = TestClock(Self.date(9, 55))
        let source = StubCalendarSource(calendars: [Self.work], events: [
            Self.event("Standup", from: Self.date(10, 0)),
            Self.event("Review", from: Self.date(10, 3)),
        ])
        let controller = Self.makeController(source, clock: clock)
        controller.start()
        defer { controller.stop() }
        #expect(controller.takeAnnouncement()?.text == "Standup in 5 min")
        #expect(controller.takeAnnouncement() == nil)

        clock.now = Self.date(10, 1)
        #expect(controller.pillStatus?.text == "Standup now")
        #expect(controller.takeAnnouncement()?.text == "Review in 2 min")
        #expect(controller.takeAnnouncement() == nil)
    }

    @Test func pluginDerivesThePillAndAnnounces() async throws {
        let suite = "CalendarPillTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = TestClock(Self.date(9, 50))
        let source = StubCalendarSource(calendars: [Self.work], events: [Self.event("Standup", from: Self.date(10, 0))])

        let registry = PluginRegistry(storageRoot: root, userDefaults: defaults)
        let entry = try await registry.register(manifest: CalendarPlugin.manifest) {
            CalendarPlugin(context: $0, source: source, now: { clock.now }, calendar: Self.calendar)
        }
        let plugin = try #require(entry.plugin as? CalendarPlugin)
        try await waitUntil { entry.context.pillStatus?.text == "Standup in 10 min" && entry.context.announcement?.text == "Standup in 10 min" }
        let first = entry.context.announcement?.id

        plugin.controller.leadMinutes = 15
        plugin.controller.showsPill = false
        try await waitUntil {
            entry.context.pillStatus == nil
                && defaults.object(forKey: "plugin.islet.calendar.leadMinutes") as? Int == 15
                && defaults.object(forKey: "plugin.islet.calendar.showsPill") as? Bool == false
        }
        plugin.controller.showsPill = true
        try await waitUntil { entry.context.pillStatus?.text == "Standup in 10 min" }
        #expect(entry.context.announcement?.id == first)
        await registry.deactivateAll()
    }
}
