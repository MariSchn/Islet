import Foundation
import IsletCore
import Observation
import os

@MainActor
@Observable
final class CalendarController {
    private(set) var authorization: CalendarAuthorization
    private(set) var calendars: [CalendarInfo] = []
    private(set) var events: [CalendarEvent] = []
    private(set) var referenceDate: Date
    var selectedCalendarIDs: Set<String>? {
        didSet {
            guard selectedCalendarIDs != oldValue else { return }
            reload()
        }
    }
    var includesAllDay: Bool {
        didSet {
            guard includesAllDay != oldValue else { return }
            reload()
        }
    }
    var leadMinutes: Int
    var showsPill: Bool
    private(set) var minuteTick = 0
    private(set) var isRunning = false
    private var announcedStarts: [String: Date] = [:]
    var isScreenVisible = false {
        didSet {
            guard isScreenVisible, !oldValue, isRunning else { return }
            reload()
        }
    }

    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored private let source: any CalendarSource
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let refreshInterval: Duration
    @ObservationIgnored private let logger: Logger
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var changeTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    init(
        source: any CalendarSource,
        selectedCalendarIDs: Set<String>? = nil,
        includesAllDay: Bool = false,
        leadMinutes: Int = CalendarController.defaultLeadMinutes,
        showsPill: Bool = true,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent,
        refreshInterval: Duration = .seconds(60),
        logger: Logger = Logger()
    ) {
        self.source = source
        self.selectedCalendarIDs = selectedCalendarIDs
        self.includesAllDay = includesAllDay
        self.leadMinutes = Self.leadMinuteChoices.contains(leadMinutes) ? leadMinutes : Self.defaultLeadMinutes
        self.showsPill = showsPill
        self.now = now
        self.calendar = calendar
        self.refreshInterval = refreshInterval
        self.logger = logger
        authorization = source.authorization
        referenceDate = now()
    }

    static let leadMinuteChoices = [5, 10, 15, 30]
    static let defaultLeadMinutes = 10
    static let startedPillDuration: TimeInterval = 5 * 60


    var agenda: CalendarAgenda {
        guard authorization == .fullAccess else { return .empty }
        return CalendarAgenda(events: events, now: referenceDate, calendar: calendar, limit: CalendarPlugin.maxVisibleRows)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        reload()
        refreshTask = Task { [weak self, refreshInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: refreshInterval)
                guard !Task.isCancelled, let self else { return }
                reload()
            }
        }
        changeTask = Task { [weak self, source] in
            for await _ in source.changes() {
                guard let self else { return }
                reload()
            }
        }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = self?.delayUntilNextMinute else { return }
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }
                referenceDate = now()
                minuteTick += 1
            }
        }
    }

    func stop() {
        isRunning = false
        refreshTask?.cancel()
        changeTask?.cancel()
        tickTask?.cancel()
        refreshTask = nil
        changeTask = nil
        tickTask = nil
    }

    private var delayUntilNextMinute: Duration {
        let elapsed = now().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60)
        return .seconds(60 - elapsed)
    }

    private var nextTimedEvent: CalendarEvent? {
        _ = minuteTick
        let now = now()
        return earliest(events.filter { !$0.isAllDay && $0.start.addingTimeInterval(Self.startedPillDuration) > now })
    }

    private var nextUpcomingEvent: CalendarEvent? {
        _ = minuteTick
        let now = now()
        return earliest(events.filter { !$0.isAllDay && $0.start > now })
    }

    private func earliest(_ events: [CalendarEvent]) -> CalendarEvent? {
        events.min { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    private func minutesUntil(_ event: CalendarEvent, from now: Date) -> Int {
        Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
    }

    private func isWithinLeadTime(_ event: CalendarEvent, at now: Date) -> Bool {
        event.start > now && event.start.timeIntervalSince(now) <= TimeInterval(leadMinutes * 60)
    }

    var pillStatus: PillStatus? {
        guard showsPill, let event = nextTimedEvent else { return nil }
        let now = now()
        let title = event.title.isEmpty ? "Untitled" : event.title
        if event.start <= now {
            return PillStatus(text: "\(title) now", systemImage: "calendar", priority: .attention, tint: event.color)
        }
        guard isWithinLeadTime(event, at: now) else { return nil }
        return PillStatus(text: "\(title) in \(minutesUntil(event, from: now)) min", systemImage: "calendar", priority: .info, tint: event.color)
    }

    var announcementCandidate: CalendarEvent? {
        guard isRunning, showsPill, let event = nextUpcomingEvent, isWithinLeadTime(event, at: now()) else { return nil }
        return announcedStarts[event.identifier] == event.start ? nil : event
    }

    func takeAnnouncement() -> PillAnnouncement? {
        guard let event = announcementCandidate else { return nil }
        let now = now()
        announcedStarts = announcedStarts.filter { $0.value.addingTimeInterval(Self.startedPillDuration) > now }
        announcedStarts[event.identifier] = event.start
        let title = event.title.isEmpty ? "Untitled" : event.title
        return PillAnnouncement(text: "\(title) in \(minutesUntil(event, from: now)) min", systemImage: "calendar", tint: event.color, priority: .info)
    }

    func reload() {
        authorization = source.authorization
        referenceDate = now()
        guard authorization == .fullAccess else {
            calendars = []
            events = []
            return
        }
        calendars = source.calendars()
        let ids = selectedCalendarIDs ?? Set(calendars.map(\.id))
        let start = calendar.startOfDay(for: referenceDate)
        guard !ids.isEmpty, let end = calendar.date(byAdding: .day, value: 2, to: start) else {
            events = []
            return
        }
        events = source.events(from: start, to: end, calendarIDs: ids)
            .filter { event in
                ids.contains(event.calendarID) && (includesAllDay || !event.isAllDay)
                    && max(event.end, event.start.addingTimeInterval(Self.startedPillDuration)) > referenceDate
            }
    }

    func requestAccess() async {
        do {
            let granted = try await source.requestAccess()
            logger.info("Calendar access \(granted ? "granted" : "not granted", privacy: .public)")
        } catch {
            logger.error("Requesting calendar access failed: \(error.localizedDescription, privacy: .public)")
        }
        reload()
    }

    func isSelected(_ calendar: CalendarInfo) -> Bool {
        selectedCalendarIDs?.contains(calendar.id) ?? true
    }

    func setSelected(_ selected: Bool, for calendar: CalendarInfo) {
        var ids = selectedCalendarIDs ?? Set(calendars.map(\.id))
        if selected {
            ids.insert(calendar.id)
        } else {
            ids.remove(calendar.id)
        }
        selectedCalendarIDs = Set(calendars.map(\.id)).isSubset(of: ids) ? nil : ids
    }
}
