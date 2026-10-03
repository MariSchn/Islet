import Foundation

struct CalendarAgenda: Equatable {
    enum Day: Equatable {
        case today
        case tomorrow

        var title: String {
            switch self {
            case .today: "Today"
            case .tomorrow: "Tomorrow"
            }
        }
    }

    struct Section: Equatable, Identifiable {
        let day: Day
        var events: [CalendarEvent]

        var id: Day { day }
    }

    static let empty = CalendarAgenda(sections: [], moreCount: 0)

    var sections: [Section]
    var moreCount: Int

    var rowCount: Int {
        sections.map(\.events.count).reduce(0, +)
    }

    init(sections: [Section], moreCount: Int) {
        self.sections = sections
        self.moreCount = moreCount
    }

    init(events: [CalendarEvent], now: Date, calendar: Calendar, limit: Int) {
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let endOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfTomorrow) ?? startOfTomorrow
        let sorted = events
            .filter { $0.end > now && $0.start < endOfTomorrow }
            .sorted { lhs, rhs in
                let lhsDay = lhs.start < startOfTomorrow ? 0 : 1
                let rhsDay = rhs.start < startOfTomorrow ? 0 : 1
                if lhsDay != rhsDay { return lhsDay < rhsDay }
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                return lhs.title < rhs.title
            }
        let visible = sorted.prefix(max(limit, 0))
        let today = visible.filter { $0.start < startOfTomorrow }
        let tomorrow = visible.filter { $0.start >= startOfTomorrow }
        sections = [Section(day: .today, events: today), Section(day: .tomorrow, events: tomorrow)].filter { !$0.events.isEmpty }
        moreCount = sorted.count - visible.count
    }
}
