import AppKit
import IsletCore
import SwiftUI

@MainActor
public final class AgentsPlugin: IsletPlugin {
    public static let manifest = PluginManifest(id: "islet.agents", displayName: "Agents", systemImage: "terminal")
    static let contentWidth: CGFloat = 520
    static let emptyContentHeight: CGFloat = 130
    static let rowHeight: CGFloat = 68
    static let rowSpacing: CGFloat = 6
    static let rowPadding: CGFloat = 16
    static let usageBarHeight: CGFloat = 22
    static let contentPadding: CGFloat = 12
    static let maxVisibleRows = 4
    static let requestPadding: CGFloat = 8
    static let requestDetailHeight: CGFloat = 30
    static let questionDetailHeight: CGFloat = 46
    static let requestButtonHeight: CGFloat = 24
    static let requestSpacing: CGFloat = 6
    static let activityEntryHeight: CGFloat = 18
    static let activityHeaderHeight: CGFloat = 16
    static let planHeight: CGFloat = 140
    static let maxContentHeight = 2 * contentPadding + CGFloat(maxVisibleRows) * rowHeight + CGFloat(maxVisibleRows - 1) * rowSpacing

    static func contentSize(for sessions: [AgentSession], expanded: Set<String>, showsUsage: Bool, showsAntigravityQuota: Bool = false, historyLength: Int) -> CGSize {
        let usage = CGFloat([showsUsage, showsAntigravityQuota].filter { $0 }.count) * (usageBarHeight + rowSpacing)
        guard !sessions.isEmpty else { return CGSize(width: contentWidth, height: emptyContentHeight + usage) }
        let rows = sessions.map { rowHeight(for: $0, expanded: expanded.contains($0.id), historyLength: historyLength) }.reduce(0, +) + CGFloat(sessions.count - 1) * rowSpacing
        return CGSize(width: contentWidth, height: min(2 * contentPadding + usage + rows, maxContentHeight + usage))
    }

    static func rowHeight(for session: AgentSession, expanded: Bool, historyLength: Int) -> CGFloat {
        rowHeight + (session.pendingRequest.map(requestHeight(for:)) ?? 0) + (expanded ? detailHeight(for: session, historyLength: historyLength) : 0)
    }

    static func visibleActivities(of session: AgentSession, historyLength: Int) -> ArraySlice<ActivityEntry> {
        session.activities.suffix(historyLength)
    }

    static func detailHeight(for session: AgentSession, historyLength: Int) -> CGFloat {
        var height = 2 * requestPadding
        if session.details.costUSD != nil {
            height += activityHeaderHeight + activityEntryHeight
        }
        if session.plan != nil {
            height += activityHeaderHeight + planHeight + requestSpacing
        }
        height += activityHeaderHeight + CGFloat(max(visibleActivities(of: session, historyLength: historyLength).count, 1)) * activityEntryHeight
        return height
    }

    static func requestHeight(for request: PendingRequest) -> CGFloat {
        switch request.kind {
        case .permission:
            return 2 * requestPadding + requestDetailHeight + requestSpacing + requestButtonHeight
        case .question(let questions):
            let options = questions.map { CGFloat($0.options.count + 1) * requestButtonHeight + CGFloat($0.options.count) * requestSpacing + ($0.multiSelect ? requestSpacing + requestButtonHeight : 0) }
            return 2 * requestPadding + questionDetailHeight(for: questions) + requestSpacing + (options.max() ?? 0)
        }
    }

    static func questionDetailHeight(for questions: [PendingRequest.Question]) -> CGFloat {
        guard !questions.contains(where: { $0.header != nil }) else { return questionDetailHeight }
        let font = NSFont.systemFont(ofSize: 12)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let width = contentWidth - 2 * contentPadding - 2 * rowPadding - (questions.count > 1 ? 22 : 0)
        let isMultiline = questions.contains { question in
            NSAttributedString(string: question.text, attributes: [.font: font])
                .boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin).height > lineHeight
        }
        return isMultiline ? 2 * lineHeight : lineHeight
    }

    private static let tokenKey = "hookToken"
    private static let remoteTokenKey = "remoteHookToken"
    private static let usageKey = "showUsage"
    private static let pillContentKey = "pillContent"
    private static let historyLengthKey = "historyLength"
    private static let alertKeys: [(key: String, value: WritableKeyPath<AlertSettings, Bool>)] = [
        ("attentionSound", \.attentionSound),
        ("attentionNotification", \.attentionNotification),
        ("finishedSound", \.finishedSound),
        ("finishedNotification", \.finishedNotification),
        ("announcesInNotch", \.announcesInNotch),
    ]
    private static let displayKeys: [(key: String, value: WritableKeyPath<DisplaySettings, Bool>)] = [
        ("showFiveHourLimit", \.showsFiveHourLimit),
        ("showWeeklyLimit", \.showsWeeklyLimit),
        ("showUsageResetTimes", \.showsResetTimes),
        ("pillShowsWorking", \.pillShowsWorking),
        ("pillShowsFinished", \.pillShowsFinished),
        ("ringKeepsFinishedSessions", \.ringKeepsFinishedSessions),
    ]

    private let context: PluginContext
    let controller: AgentsController

    public init(context: PluginContext) {
        self.context = context
        let settings = context.settings
        let token = Self.storedToken(forKey: Self.tokenKey, in: settings)
        let remoteToken = Self.storedToken(forKey: Self.remoteTokenKey, in: settings)
        var display = Self.load(DisplaySettings(), Self.displayKeys, from: settings)
        display.pillContent = settings.value(forKey: Self.pillContentKey).flatMap(DisplaySettings.PillContent.init(rawValue:)) ?? display.pillContent
        display.historyLength = settings.value(forKey: Self.historyLengthKey) ?? display.historyLength
        let controller = AgentsController(
            token: token,
            remoteToken: remoteToken,
            home: URL.homeDirectory,
            alerts: Self.load(AlertSettings(), Self.alertKeys, from: settings),
            display: display,
            showsUsage: settings.value(forKey: Self.usageKey) ?? false,
            storageDirectory: context.storageDirectory,
            logger: context.logger
        )
        self.controller = controller

        context.observe({ controller.remoteToken }) { settings.set($0, forKey: Self.remoteTokenKey) }
        context.observe({ controller.showsUsage }) { settings.set($0, forKey: Self.usageKey) }
        context.observe({ controller.alerts }) { Self.save($0, Self.alertKeys, to: settings) }
        context.observe({ controller.display }) { display in
            Self.save(display, Self.displayKeys, to: settings)
            settings.set(display.pillContent.rawValue, forKey: Self.pillContentKey)
            settings.set(display.historyLength, forKey: Self.historyLengthKey)
        }
        context.derive(\.pillStatus) { controller.store.pillStatus(for: controller.display) }
        context.derive(\.contentSize) {
            Self.contentSize(for: controller.store.orderedSessions, expanded: controller.expandedSessionIDs, showsUsage: controller.showsUsageBar, showsAntigravityQuota: controller.visibleAntigravityQuota != nil, historyLength: controller.display.historyLength)
        }
        context.observe({ controller.store.sessions }) { [unowned context] _ in
            for announcement in controller.sessionsDidChange() {
                context.announce(announcement)
            }
        }
    }

    public func activate() async throws {
        await controller.start()
    }

    public func deactivate() async {
        await controller.stop()
    }

    public func makeScreen() -> AnyView {
        AnyView(AgentsScreen(controller: controller))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(AgentsSettings(controller: controller))
    }

    private static func storedToken(forKey key: String, in settings: PluginSettings) -> String {
        if let stored: String = settings.value(forKey: key) { return stored }
        let token = HookServer.makeToken()
        settings.set(token, forKey: key)
        return token
    }

    private static func load<Settings>(_ defaults: Settings, _ keys: [(key: String, value: WritableKeyPath<Settings, Bool>)], from settings: PluginSettings) -> Settings {
        keys.reduce(into: defaults) { loaded, entry in
            loaded[keyPath: entry.value] = settings.value(forKey: entry.key) ?? loaded[keyPath: entry.value]
        }
    }

    private static func save<Settings>(_ value: Settings, _ keys: [(key: String, value: WritableKeyPath<Settings, Bool>)], to settings: PluginSettings) {
        for entry in keys {
            settings.set(value[keyPath: entry.value], forKey: entry.key)
        }
    }
}
