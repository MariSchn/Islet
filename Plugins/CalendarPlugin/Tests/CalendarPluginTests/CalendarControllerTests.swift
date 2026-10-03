import Foundation
import IsletCore
import SwiftUI
import Testing
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

@MainActor
struct CalendarControllerTests {
    static let timeZone = TimeZone(identifier: "Europe/Berlin")!
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }()
    static let gray = Color.Resolved(red: 0.5, green: 0.5, blue: 0.5)
    static let work = CalendarInfo(id: "work", title: "Work", accountID: "icloud", account: "iCloud", color: gray)
    static let home = CalendarInfo(id: "home", title: "Home", accountID: "google", account: "Google", color: gray)

    static func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    static func event(_ id: String, calendar: CalendarInfo = work, from start: Date, to end: Date, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(identifier: id, title: id, start: start, end: end, isAllDay: allDay, calendarID: calendar.id, color: gray, location: nil)
    }

    static func makeController(_ source: StubCalendarSource, now: Date = date(3, 22, 30), selected: Set<String>? = nil, includesAllDay: Bool = false, refreshInterval: Duration = .seconds(60)) -> CalendarController {
        CalendarController(source: source, selectedCalendarIDs: selected, includesAllDay: includesAllDay, now: { now }, calendar: calendar, refreshInterval: refreshInterval)
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
    }

    @Test func showsOnlySelectedCalendars() {
        let source = StubCalendarSource(calendars: [Self.work, Self.home], events: [
            Self.event("standup", from: Self.date(4, 9), to: Self.date(4, 10)),
            Self.event("dinner", calendar: Self.home, from: Self.date(4, 19), to: Self.date(4, 21)),
        ])
        let controller = Self.makeController(source, selected: ["home"])
        controller.reload()
        #expect(controller.events.map(\.identifier) == ["dinner"])

        controller.selectedCalendarIDs = nil
        #expect(Set(controller.events.map(\.identifier)) == ["standup", "dinner"])

        controller.setSelected(false, for: Self.home)
        #expect(controller.selectedCalendarIDs == ["work"])
        #expect(controller.events.map(\.identifier) == ["standup"])

        controller.setSelected(true, for: Self.home)
        #expect(controller.selectedCalendarIDs == nil)

        controller.selectedCalendarIDs = []
        #expect(controller.events.isEmpty)
    }

    @Test func includesAllDayEventsOnlyWhenEnabled() {
        let source = StubCalendarSource(calendars: [Self.work], events: [
            Self.event("holiday", from: Self.date(4, 0), to: Self.date(5, 0), allDay: true),
            Self.event("standup", from: Self.date(4, 9), to: Self.date(4, 10)),
        ])
        let controller = Self.makeController(source)
        controller.reload()
        #expect(controller.events.map(\.identifier) == ["standup"])

        controller.includesAllDay = true
        #expect(controller.agenda.sections.first?.events.map(\.identifier) == ["holiday", "standup"])
    }

    @Test func dropsEndedEvents() throws {
        let source = StubCalendarSource(calendars: [Self.work], events: [
            Self.event("lunch", from: Self.date(3, 12), to: Self.date(3, 13)),
            Self.event("call", from: Self.date(3, 22), to: Self.date(3, 23)),
        ])
        let controller = Self.makeController(source)
        controller.reload()
        #expect(controller.events.map(\.identifier) == ["call"])
        let call = try #require(controller.events.first)
        #expect(call.isInProgress(at: Self.date(3, 22, 30)))
        #expect(call.timeLabel(at: Self.date(3, 22, 30)) == "now · 30 min left")
    }

    @Test func groupsIntoTodayAndTomorrowAcrossMidnight() {
        let source = StubCalendarSource(calendars: [Self.work], events: [
            Self.event("late", from: Self.date(3, 23, 30), to: Self.date(4, 0, 30)),
            Self.event("call", from: Self.date(3, 22), to: Self.date(3, 23)),
            Self.event("breakfast", from: Self.date(4, 8), to: Self.date(4, 9)),
            Self.event("midnight", from: Self.date(4, 0), to: Self.date(4, 0, 15)),
            Self.event("later", from: Self.date(5, 9), to: Self.date(5, 10)),
        ])
        let controller = Self.makeController(source)
        controller.reload()
        let agenda = controller.agenda
        #expect(agenda.sections.map(\.day) == [.today, .tomorrow])
        #expect(agenda.sections[0].events.map(\.identifier) == ["call", "late"])
        #expect(agenda.sections[1].events.map(\.identifier) == ["midnight", "breakfast"])
        #expect(agenda.moreCount == 0)
    }

    @Test func omitsEmptySections() {
        let source = StubCalendarSource(calendars: [Self.work], events: [
            Self.event("breakfast", from: Self.date(4, 8), to: Self.date(4, 9)),
        ])
        let controller = Self.makeController(source)
        controller.reload()
        #expect(controller.agenda.sections.map(\.day) == [.tomorrow])

        source.eventList = []
        controller.reload()
        #expect(controller.agenda.sections.isEmpty)
        #expect(controller.agenda.rowCount == 0)
    }

    @Test func limitsRowsAndCountsTheRest() {
        let today = (0..<4).map { Self.event("today\($0)", from: Self.date(3, 23, $0 * 10), to: Self.date(3, 23, $0 * 10 + 5)) }
        let tomorrow = (0..<5).map { Self.event("tomorrow\($0)", from: Self.date(4, 9 + $0), to: Self.date(4, 10 + $0)) }
        let source = StubCalendarSource(calendars: [Self.work], events: tomorrow + today)
        let controller = Self.makeController(source)
        controller.reload()
        let agenda = controller.agenda
        #expect(agenda.rowCount == CalendarPlugin.maxVisibleRows)
        #expect(agenda.sections[0].events.count == 4)
        #expect(agenda.sections[1].events.map(\.identifier) == ["tomorrow0", "tomorrow1"])
        #expect(agenda.moreCount == 3)
    }

    @Test func showsNothingWithoutAccessAndNeverRequestsItOnStart() async throws {
        let source = StubCalendarSource(authorization: .notDetermined, calendars: [Self.work], events: [
            Self.event("breakfast", from: Self.date(4, 8), to: Self.date(4, 9)),
        ])
        let controller = Self.makeController(source)
        controller.start()
        defer { controller.stop() }
        #expect(source.accessRequests == 0)
        #expect(controller.authorization == .notDetermined)
        #expect(controller.events.isEmpty)
        #expect(controller.calendars.isEmpty)

        await controller.requestAccess()
        #expect(source.accessRequests == 1)
        #expect(controller.authorization == .fullAccess)
        #expect(controller.events.map(\.identifier) == ["breakfast"])
    }

    @Test func reloadsOnChangesAndWhenTheScreenBecomesVisible() async throws {
        let source = StubCalendarSource(calendars: [Self.work])
        let controller = Self.makeController(source)
        controller.start()
        defer { controller.stop() }
        #expect(controller.events.isEmpty)

        source.eventList = [Self.event("breakfast", from: Self.date(4, 8), to: Self.date(4, 9))]
        controller.isScreenVisible = true
        #expect(controller.events.count == 1)

        source.eventList = []
        try await waitUntil {
            source.notifyChange()
            return controller.events.isEmpty
        }
    }

    @Test func reloadsPeriodicallyWhileRunning() async throws {
        let source = StubCalendarSource(calendars: [Self.work])
        let controller = Self.makeController(source, refreshInterval: .milliseconds(20))
        controller.start()
        #expect(controller.events.isEmpty)

        source.eventList = [Self.event("breakfast", from: Self.date(4, 8), to: Self.date(4, 9))]
        try await waitUntil { controller.events.count == 1 }

        controller.stop()
        #expect(!controller.isRunning)
    }

    @Test func persistsSettings() async throws {
        let suite = "CalendarControllerTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = StubCalendarSource(calendars: [Self.work, Self.home])

        let registry = PluginRegistry(storageRoot: root, userDefaults: defaults)
        let entry = try await registry.register(manifest: CalendarPlugin.manifest) { CalendarPlugin(context: $0, source: source) }
        let plugin = try #require(entry.plugin as? CalendarPlugin)
        #expect(entry.state.isActive)
        try await waitUntil { entry.context.contentSize == CalendarPlugin.contentSize(sectionCount: 0, rowCount: 0, hasMoreLine: false) }
        #expect(defaults.object(forKey: "plugin.islet.calendar.calendars") == nil)
        #expect(defaults.object(forKey: "plugin.islet.calendar.includesAllDay") == nil)

        plugin.controller.setSelected(false, for: Self.home)
        plugin.controller.includesAllDay = true
        try await waitUntil {
            defaults.stringArray(forKey: "plugin.islet.calendar.calendars") == ["work"]
                && defaults.object(forKey: "plugin.islet.calendar.includesAllDay") as? Bool == true
        }
        await registry.deactivateAll()

        let reloaded = PluginRegistry(storageRoot: root, userDefaults: defaults)
        let second = try await reloaded.register(manifest: CalendarPlugin.manifest) { CalendarPlugin(context: $0, source: source) }
        let restored = try #require(second.plugin as? CalendarPlugin)
        #expect(second.state.isActive)
        #expect(restored.controller.selectedCalendarIDs == ["work"])
        #expect(restored.controller.includesAllDay)

        restored.controller.setSelected(true, for: Self.home)
        try await waitUntil { defaults.object(forKey: "plugin.islet.calendar.calendars") == nil }
        await reloaded.deactivateAll()
    }
}
