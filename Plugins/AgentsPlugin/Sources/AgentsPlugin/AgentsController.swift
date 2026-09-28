import Foundation
import IsletCore
import Observation

@MainActor
@Observable
final class AgentsController {
    let store: AgentSessionStore
    let installer: HookInstaller
    let codexInstaller: HookInstaller
    private(set) var isHookInstalled: Bool
    private(set) var isCodexHookInstalled: Bool
    private(set) var serverError: String?
    private(set) var expandedSessionIDs: Set<String> = []
    let usage: UsageMonitor
    var showsUsage: Bool {
        get { usage.isEnabled }
        set { usage.isEnabled = newValue }
    }
    var visibleUsage: ClaudeUsage? {
        guard usage.isEnabled, let current = usage.usage else { return nil }
        return display.visibleUsage(current)
    }
    var showsUsageBar: Bool { visibleUsage != nil }

    func shouldAnnounce(_ announcement: PillAnnouncement) -> Bool {
        alerts.announcesInNotch && (announcement.priority == .attention || display.pillShowsFinished)
    }
    var display: DisplaySettings
    var alerts: AlertSettings {
        didSet { alerter.settings = alerts }
    }

    let interruptions: InterruptionMonitor
    private let processes: ProcessMonitor
    private let server: HookServer
    private let alerter: SessionAlerter

    init(token: String, claudeDirectory: URL, codexDirectory: URL, port: UInt16 = HookServer.defaultPort, alerts: AlertSettings = AlertSettings(), display: DisplaySettings = DisplaySettings(), showsUsage: Bool = false, usage: UsageMonitor? = nil) {
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

    func start() async {
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

    var isCodexAvailable: Bool {
        isCodexHookInstalled || FileManager.default.fileExists(atPath: codexInstaller.directory.path)
    }

    func stop() async {
        await server.stop()
        usage.stop()
        interruptions.stop()
        processes.stop()
    }

    func refreshInstallState() {
        isHookInstalled = installer.isInstalled
        isCodexHookInstalled = codexInstaller.isInstalled
        Task { [server] in
            if await !server.isListening, serverError == nil {
                serverError = "The hook server stopped listening on 127.0.0.1:\(server.port). Restart Islet."
            }
        }
    }

    var isAnyHookInstalled: Bool {
        isHookInstalled || isCodexHookInstalled
    }

    func installHooks(for agent: AgentSession.Agent = .claudeCode) throws {
        try installer(for: agent).install()
        refreshInstallState()
    }

    func uninstallHooks(for agent: AgentSession.Agent = .claudeCode) throws {
        try installer(for: agent).uninstall()
        refreshInstallState()
    }

    func isHookInstalled(for agent: AgentSession.Agent) -> Bool {
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

    func decide(_ requestID: UUID, _ decision: PermissionDecision) {
        store.decide(requestID, decision)
    }

    func toggleExpanded(_ sessionID: String) {
        if expandedSessionIDs.remove(sessionID) == nil {
            expandedSessionIDs.insert(sessionID)
        }
    }
}
