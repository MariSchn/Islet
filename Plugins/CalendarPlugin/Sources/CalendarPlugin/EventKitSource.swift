import AppKit
import EventKit
import SwiftUI

@MainActor
final class EventKitSource: CalendarSource {
    private let store = EKEventStore()

    var authorization: CalendarAuthorization {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .fullAccess: .fullAccess
        default: .denied
        }
    }

    func requestAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            store.requestFullAccessToEvents { @Sendable granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func calendars() -> [CalendarInfo] {
        store.calendars(for: .event).map { calendar in
            CalendarInfo(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                accountID: calendar.source?.sourceIdentifier ?? "",
                account: calendar.source?.title ?? "",
                color: Self.resolved(calendar.color)
            )
        }
    }

    func events(from start: Date, to end: Date, calendarIDs: Set<String>) -> [CalendarEvent] {
        let calendars = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate).map { event in
            CalendarEvent(
                identifier: event.eventIdentifier ?? event.calendarItemIdentifier,
                title: event.title ?? "",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                calendarID: event.calendar.calendarIdentifier,
                color: Self.resolved(event.calendar.color),
                location: event.location
            )
        }
    }

    func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func resolved(_ color: NSColor?) -> Color.Resolved {
        guard let color = color?.usingColorSpace(.sRGB) else { return Color.Resolved(red: 0.5, green: 0.5, blue: 0.5) }
        return Color.Resolved(red: Float(color.redComponent), green: Float(color.greenComponent), blue: Float(color.blueComponent))
    }
}
