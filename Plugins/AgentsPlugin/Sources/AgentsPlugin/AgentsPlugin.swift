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

    static func contentSize(for sessions: [AgentSession], expanded: Set<String>, showsUsage: Bool, historyLength: Int) -> CGSize {
        let usage = showsUsage ? usageBarHeight + rowSpacing : 0
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
            let options = questions.map { CGFloat($0.options.count) * requestButtonHeight + CGFloat($0.options.count - 1) * requestSpacing + ($0.multiSelect ? requestSpacing + requestButtonHeight : 0) }
            return 2 * requestPadding + questionDetailHeight + requestSpacing + (options.max() ?? 0)
        }
    }

    private static let tokenKey = "hookToken"
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
    ]

    private let context: PluginContext
    let controller: AgentsController

    public init(context: PluginContext) {
        self.context = context
        let settings = context.settings
        let token: String
        if let stored: String = settings.value(forKey: Self.tokenKey) {
            token = stored
        } else {
            token = Self.makeToken()
            settings.set(token, forKey: Self.tokenKey)
        }
        var display = Self.load(DisplaySettings(), Self.displayKeys, from: settings)
        display.pillContent = settings.value(forKey: Self.pillContentKey).flatMap(DisplaySettings.PillContent.init(rawValue:)) ?? display.pillContent
        display.historyLength = settings.value(forKey: Self.historyLengthKey) ?? display.historyLength
        let controller = AgentsController(
            token: token,
            claudeDirectory: URL.homeDirectory.appending(path: ".claude", directoryHint: .isDirectory),
            codexDirectory: URL.homeDirectory.appending(path: ".codex", directoryHint: .isDirectory),
            alerts: Self.load(AlertSettings(), Self.alertKeys, from: settings),
            display: display,
            showsUsage: settings.value(forKey: Self.usageKey) ?? false
        )
        self.controller = controller

        context.observe({ controller.showsUsage }) { settings.set($0, forKey: Self.usageKey) }
        context.observe({ controller.alerts }) { Self.save($0, Self.alertKeys, to: settings) }
        context.observe({ controller.display }) { display in
            Self.save(display, Self.displayKeys, to: settings)
            settings.set(display.pillContent.rawValue, forKey: Self.pillContentKey)
            settings.set(display.historyLength, forKey: Self.historyLengthKey)
        }
        context.derive(\.pillStatus) { controller.store.pillStatus(for: controller.display) }
        context.derive(\.contentSize) {
            Self.contentSize(for: controller.store.sessions, expanded: controller.expandedSessionIDs, showsUsage: controller.showsUsageBar, historyLength: controller.display.historyLength)
        }
        var announcer = StatusAnnouncer()
        context.observe({ controller.store.sessions }) { [unowned context] sessions in
            if let announcement = announcer.announcement(for: sessions), controller.shouldAnnounce(announcement) {
                context.announce(announcement)
            }
            controller.interruptions.track(sessions)
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

    private static func makeToken() -> String {
        (0..<32).map { _ in "0123456789abcdef".randomElement()! }.reduce(into: "") { $0.append($1) }
    }
}

@MainActor
@Observable
public final class AgentsController {
    public let store: AgentSessionStore
    public let installer: HookInstaller
    public let codexInstaller: HookInstaller
    public private(set) var isHookInstalled: Bool
    public private(set) var isCodexHookInstalled: Bool
    public private(set) var serverError: String?
    public private(set) var expandedSessionIDs: Set<String> = []
    public let usage: UsageMonitor
    public var showsUsage: Bool {
        get { usage.isEnabled }
        set { usage.isEnabled = newValue }
    }
    public var visibleUsage: ClaudeUsage? {
        guard usage.isEnabled, let current = usage.usage else { return nil }
        return display.visibleUsage(current)
    }
    public var showsUsageBar: Bool { visibleUsage != nil }

    func shouldAnnounce(_ announcement: PillAnnouncement) -> Bool {
        alerts.announcesInNotch && (announcement.priority == .attention || display.pillShowsFinished)
    }
    public var display: DisplaySettings
    public var alerts: AlertSettings {
        didSet { alerter.settings = alerts }
    }

    let interruptions: InterruptionMonitor
    private let processes: ProcessMonitor
    private let server: HookServer
    private let alerter: SessionAlerter

    public init(token: String, claudeDirectory: URL, codexDirectory: URL, port: UInt16 = HookServer.defaultPort, alerts: AlertSettings = AlertSettings(), display: DisplaySettings = DisplaySettings(), showsUsage: Bool = false, usage: UsageMonitor? = nil) {
        let store = AgentSessionStore()
        self.store = store
        self.usage = usage ?? UsageMonitor(isEnabled: showsUsage)
        installer = HookInstaller(agent: .claudeCode, directory: claudeDirectory, port: port, token: token)
        codexInstaller = HookInstaller(agent: .codex, directory: codexDirectory, port: port, token: token)
        isHookInstalled = installer.isInstalled
        isCodexHookInstalled = codexInstaller.isInstalled
        server = HookServer(port: port, token: token, installScript: HookInstaller.remoteInstallScript(for: [installer, codexInstaller])) { event in
            await store.handle(event)
        }
        let alerter = SessionAlerter(settings: alerts)
        self.alerter = alerter
        self.alerts = alerts
        self.display = display
        store.onAlert = { alerter.handle($0) }
        interruptions = InterruptionMonitor { store.markInterrupted($0) }
        processes = ProcessMonitor { store.removeExitedSessions(isRunning: ProcessMonitor.isRunning) }
    }

    public func start() async {
        do {
            try await server.start()
            serverError = nil
        } catch {
            serverError = "Could not listen on 127.0.0.1:\(server.port). Is another app using the port?"
        }
        for installer in [installer, codexInstaller] where installer.needsUpgrade {
            try? installer.install()
        }
        refreshInstallState()
        usage.start()
        interruptions.start()
        processes.start()
    }

    public var isCodexAvailable: Bool {
        isCodexHookInstalled || FileManager.default.fileExists(atPath: codexInstaller.directory.path)
    }

    public func stop() async {
        await server.stop()
        usage.stop()
        interruptions.stop()
        processes.stop()
    }

    public func refreshInstallState() {
        isHookInstalled = installer.isInstalled
        isCodexHookInstalled = codexInstaller.isInstalled
        Task { [server] in
            if await !server.isListening, serverError == nil {
                serverError = "The hook server stopped listening on 127.0.0.1:\(server.port). Restart Islet."
            }
        }
    }

    public var isAnyHookInstalled: Bool {
        isHookInstalled || isCodexHookInstalled
    }

    public func installHooks(for agent: AgentSession.Agent = .claudeCode) throws {
        try installer(for: agent).install()
        refreshInstallState()
    }

    public func uninstallHooks(for agent: AgentSession.Agent = .claudeCode) throws {
        try installer(for: agent).uninstall()
        refreshInstallState()
    }

    public func isHookInstalled(for agent: AgentSession.Agent) -> Bool {
        switch agent {
        case .claudeCode: isHookInstalled
        case .codex: isCodexHookInstalled
        }
    }

    private func installer(for agent: AgentSession.Agent) -> HookInstaller {
        switch agent {
        case .claudeCode: installer
        case .codex: codexInstaller
        }
    }

    public func decide(_ requestID: UUID, _ decision: PermissionDecision) {
        store.decide(requestID, decision)
    }

    public func toggleExpanded(_ sessionID: String) {
        if expandedSessionIDs.remove(sessionID) == nil {
            expandedSessionIDs.insert(sessionID)
        }
    }
}
