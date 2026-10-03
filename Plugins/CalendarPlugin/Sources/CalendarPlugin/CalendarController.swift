import Foundation
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

    init(
        source: any CalendarSource,
        selectedCalendarIDs: Set<String>? = nil,
        includesAllDay: Bool = false,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent,
        refreshInterval: Duration = .seconds(60),
        logger: Logger = Logger()
    ) {
        self.source = source
        self.selectedCalendarIDs = selectedCalendarIDs
        self.includesAllDay = includesAllDay
        self.now = now
        self.calendar = calendar
        self.refreshInterval = refreshInterval
        self.logger = logger
        authorization = source.authorization
        referenceDate = now()
    }

    var isRunning: Bool {
        refreshTask != nil
    }

    var agenda: CalendarAgenda {
        guard authorization == .fullAccess else { return .empty }
        return CalendarAgenda(events: events, now: referenceDate, calendar: calendar, limit: CalendarPlugin.maxVisibleRows)
    }

    func start() {
        guard refreshTask == nil else { return }
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
    }

    func stop() {
        refreshTask?.cancel()
        changeTask?.cancel()
        refreshTask = nil
        changeTask = nil
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
            .filter { ids.contains($0.calendarID) && (includesAllDay || !$0.isAllDay) && $0.end > referenceDate }
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
