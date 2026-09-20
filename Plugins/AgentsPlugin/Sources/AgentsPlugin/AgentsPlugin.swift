import IsletCore
import SwiftUI

@MainActor
public final class AgentsPlugin: IsletPlugin {
    public static let manifest = PluginManifest(id: "islet.agents", displayName: "Agents", systemImage: "terminal")
    static let contentWidth: CGFloat = 520
    static let emptyContentHeight: CGFloat = 130
    static let rowHeight: CGFloat = 54
    static let rowSpacing: CGFloat = 4
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

    static func contentSize(for sessions: [AgentSession], expanded: Set<String>) -> CGSize {
        guard !sessions.isEmpty else { return CGSize(width: contentWidth, height: emptyContentHeight) }
        let rows = sessions.map { rowHeight(for: $0, expanded: expanded.contains($0.id)) }.reduce(0, +) + CGFloat(sessions.count - 1) * rowSpacing
        return CGSize(width: contentWidth, height: min(2 * contentPadding + rows, maxContentHeight))
    }

    static func rowHeight(for session: AgentSession, expanded: Bool) -> CGFloat {
        rowHeight + (session.pendingRequest.map(requestHeight(for:)) ?? 0) + (expanded ? detailHeight(for: session) : 0)
    }

    static func detailHeight(for session: AgentSession) -> CGFloat {
        var height = 2 * requestPadding
        if session.plan != nil {
            height += activityHeaderHeight + planHeight + requestSpacing
        }
        height += activityHeaderHeight + CGFloat(max(session.activities.count, 1)) * activityEntryHeight
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

    private let context: PluginContext
    private let controller: AgentsController

    public init(context: PluginContext) {
        self.context = context
        let token: String
        if let stored: String = context.settings.value(forKey: Self.tokenKey) {
            token = stored
        } else {
            token = Self.makeToken()
            context.settings.set(token, forKey: Self.tokenKey)
        }
        controller = AgentsController(
            token: token,
            claudeDirectory: URL.homeDirectory.appending(path: ".claude", directoryHint: .isDirectory)
        )
        controller.store.onChange = { [context, controller] in
            context.pillStatus = controller.store.pillStatus
            context.contentSize = Self.contentSize(for: controller.store.sessions, expanded: controller.expandedSessionIDs)
        }
    }

    public func activate() async throws {
        context.contentSize = Self.contentSize(for: controller.store.sessions, expanded: controller.expandedSessionIDs)
        await controller.start()
    }

    public func deactivate() async {
        await controller.stop()
        context.pillStatus = nil
    }

    public func makeScreen() -> AnyView {
        AnyView(AgentsScreen(controller: controller))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(AgentsSettings(controller: controller))
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
    public private(set) var isHookInstalled: Bool
    public private(set) var serverError: String?
    public private(set) var expandedSessionIDs: Set<String> = []

    private let server: HookServer

    public init(token: String, claudeDirectory: URL, port: UInt16 = HookServer.defaultPort) {
        let store = AgentSessionStore()
        self.store = store
        installer = HookInstaller(claudeDirectory: claudeDirectory, port: port, token: token)
        isHookInstalled = installer.isInstalled
        server = HookServer(port: port, token: token) { event in
            await store.handle(event)
        }
    }

    public func start() async {
        do {
            try await server.start()
            serverError = nil
        } catch {
            serverError = "Could not listen on 127.0.0.1:\(server.port). Is another app using the port?"
        }
        if installer.needsUpgrade {
            try? installer.install()
        }
        refreshInstallState()
    }

    public func stop() async {
        await server.stop()
    }

    public func refreshInstallState() {
        isHookInstalled = installer.isInstalled
    }

    public func installHooks() throws {
        try installer.install()
        refreshInstallState()
    }

    public func uninstallHooks() throws {
        try installer.uninstall()
        refreshInstallState()
    }

    public func decide(_ requestID: UUID, _ decision: PermissionDecision) {
        store.decide(requestID, decision)
    }

    public func toggleExpanded(_ sessionID: String) {
        if expandedSessionIDs.remove(sessionID) == nil {
            expandedSessionIDs.insert(sessionID)
        }
        store.onChange?()
    }
}
