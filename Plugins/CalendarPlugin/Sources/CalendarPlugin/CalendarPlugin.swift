import IsletCore
import SwiftUI

@MainActor
public final class CalendarPlugin: IsletPlugin {
    public static let manifest = PluginManifest(id: "islet.calendar", displayName: "Calendar", systemImage: "calendar", summary: "Today's and tomorrow's events, with a Join button for video calls.", tint: .red)
    static let contentWidth: CGFloat = 420
    static let contentPadding: CGFloat = 12
    static let headerHeight: CGFloat = 18
    static let rowHeight: CGFloat = 34
    static let sectionSpacing: CGFloat = 6
    static let moreLineHeight: CGFloat = 18
    static let emptyContentHeight: CGFloat = 120
    static let maxVisibleRows = 6

    static func contentSize(sectionCount: Int, rowCount: Int, hasMoreLine: Bool) -> CGSize {
        guard rowCount > 0 else { return CGSize(width: contentWidth, height: emptyContentHeight) }
        let sections = CGFloat(sectionCount) * headerHeight + CGFloat(max(sectionCount - 1, 0)) * sectionSpacing
        let height = 2 * contentPadding + sections + CGFloat(rowCount) * rowHeight + (hasMoreLine ? moreLineHeight : 0)
        return CGSize(width: contentWidth, height: height)
    }

    static func contentSize(for agenda: CalendarAgenda) -> CGSize {
        contentSize(sectionCount: agenda.sections.count, rowCount: agenda.rowCount, hasMoreLine: agenda.moreCount > 0)
    }

    static let calendarsKey = "calendars"
    static let includesAllDayKey = "includesAllDay"
    static let leadMinutesKey = "leadMinutes"
    static let showsPillKey = "showsPill"

    let controller: CalendarController

    public convenience init(context: PluginContext) {
        self.init(context: context, source: EventKitSource())
    }

    init(context: PluginContext, source: any CalendarSource, now: @escaping () -> Date = Date.init, calendar: Calendar = .autoupdatingCurrent) {
        let settings = context.settings
        let stored: [String]? = settings.value(forKey: Self.calendarsKey)
        let controller = CalendarController(
            source: source,
            selectedCalendarIDs: stored.map(Set.init),
            includesAllDay: settings.value(forKey: Self.includesAllDayKey) ?? false,
            leadMinutes: settings.value(forKey: Self.leadMinutesKey) ?? CalendarController.defaultLeadMinutes,
            showsPill: settings.value(forKey: Self.showsPillKey) ?? true,
            now: now,
            calendar: calendar,
            logger: context.logger
        )
        self.controller = controller
        context.derive(\.contentSize) { Self.contentSize(for: controller.agenda) }
        context.derive(\.pillStatus) { controller.pillStatus }
        context.observe({ controller.selectedCalendarIDs }) { settings.set($0.map { $0.sorted() }, forKey: Self.calendarsKey) }
        context.observe({ controller.includesAllDay }) { settings.set($0, forKey: Self.includesAllDayKey) }
        context.observe({ controller.leadMinutes }) { settings.set($0, forKey: Self.leadMinutesKey) }
        context.observe({ controller.showsPill }) { settings.set($0, forKey: Self.showsPillKey) }
        context.observe({ controller.announcementCandidate }) { [unowned context] _ in
            if let announcement = controller.takeAnnouncement() {
                context.announce(announcement)
            }
        }
        context.observe({ [unowned context] in context.isScreenVisible }) { controller.isScreenVisible = $0 }
    }

    public func activate() async throws {
        controller.start()
    }

    public func deactivate() async {
        controller.stop()
    }

    public func makeScreen() -> AnyView {
        AnyView(CalendarScreen(controller: controller))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(CalendarSettings(controller: controller))
    }
}
