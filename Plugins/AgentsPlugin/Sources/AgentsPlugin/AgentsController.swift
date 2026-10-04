import Foundation
import IsletCore
import Observation
import os

@MainActor
@Observable
final class AgentsController {
    let store: AgentSessionStore
    let installer: HookInstaller
    let codexInstaller: HookInstaller
    let antigravityInstaller: HookInstaller
    let statusLineInstaller: StatusLineInstaller
    let antigravityStatusLineInstaller: StatusLineInstaller
    private(set) var isHookInstalled: Bool
    private(set) var isCodexHookInstalled: Bool
    private(set) var isAntigravityHookInstalled: Bool
    private(set) var statusLineState: StatusLineInstaller.State
    private(set) var antigravityStatusLineState: StatusLineInstaller.State
    private(set) var serverError: String?
    private(set) var expandedSessionIDs: Set<String> = []
    private(set) var mutedSessionIDs: Set<String> = []
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
    var visibleAntigravityQuota: AntigravityQuota? {
        usage.isEnabled ? usage.antigravityQuota : nil
    }
    var dailyCost: Double { usage.dailyCost }

    func shouldAnnounce(_ announcement: PillAnnouncement) -> Bool {
        alerts.announcesInNotch && (announcement.priority == .attention || display.pillShowsFinished)
    }
    func shouldAlert(_ alert: AgentSessionStore.Alert) -> Bool {
        !mutedSessionIDs.contains(alert.session.id)
    }

    func toggleMute(_ sessionID: String) {
        if !mutedSessionIDs.insert(sessionID).inserted {
            mutedSessionIDs.remove(sessionID)
        }
    }

    func pruneMutedSessions() {
        let ids = Set(store.sessions.map(\.id))
        if !mutedSessionIDs.isSubset(of: ids) {
            mutedSessionIDs.formIntersection(ids)
        }
    }

    var display: DisplaySettings
    var alerts: AlertSettings {
        didSet { alerter.settings = alerts }
    }

    let interruptions: InterruptionMonitor
    private let processes: ProcessMonitor
    private let server: HookServer
    private let alerter: SessionAlerter
    private let persistence: SessionPersistence?
    private let saveDelay: Duration
    private var saveTask: Task<Void, Never>?
    private var hasRestored = false

    init(token: String, claudeDirectory: URL, codexDirectory: URL, antigravityDirectory: URL, port: UInt16 = HookServer.defaultPort, alerts: AlertSettings = AlertSettings(), display: DisplaySettings = DisplaySettings(), showsUsage: Bool = false, usage: UsageMonitor? = nil, storageDirectory: URL? = nil, saveDelay: Duration = .seconds(1), logger: Logger = Logger()) {
        persistence = storageDirectory.map { SessionPersistence(directory: $0, logger: logger) }
        self.saveDelay = saveDelay
        let store = AgentSessionStore()
        self.store = store
        self.usage = usage ?? UsageMonitor(isEnabled: showsUsage)
        installer = HookInstaller(agent: .claudeCode, directory: claudeDirectory, port: port, token: token)
        codexInstaller = HookInstaller(agent: .codex, directory: codexDirectory, port: port, token: token)
        antigravityInstaller = HookInstaller(agent: .antigravity, directory: antigravityDirectory, port: port, token: token)
        statusLineInstaller = StatusLineInstaller(directory: claudeDirectory, port: port, token: token)
        antigravityStatusLineInstaller = StatusLineInstaller(agent: .antigravity, directory: antigravityDirectory.deletingLastPathComponent().appending(path: "antigravity-cli", directoryHint: .isDirectory), port: port, token: token)
        isHookInstalled = installer.isInstalled
        isCodexHookInstalled = codexInstaller.isInstalled
        isAntigravityHookInstalled = antigravityInstaller.isInstalled
        statusLineState = statusLineInstaller.state
        antigravityStatusLineState = antigravityStatusLineInstaller.state
        let usage = self.usage
        server = HookServer(port: port, token: token, installScript: HookInstaller.remoteInstallScript(for: [installer, codexInstaller])) { update in
            logger.debug("Status line update for \(update.sessionID, privacy: .public): 5h \(update.usage?.fiveHour.map { "\($0.utilization)%" } ?? "absent", privacy: .public), 7d \(update.usage?.sevenDay.map { "\($0.utilization)%" } ?? "absent", privacy: .public)")
            await store.applyStatusLine(update)
            if let limits = update.usage {
                await usage.receive(limits)
            }
            if let quota = update.antigravityQuota {
                await usage.receive(quota)
            }
            if !update.isAntigravity, let cost = update.details.costUSD {
                await usage.record(sessionID: update.sessionID, cost: cost)
            }
        } handler: { event in
            await store.handle(event)
        }
        let alerter = SessionAlerter(settings: alerts)
        self.alerter = alerter
        self.alerts = alerts
        self.display = display
        interruptions = InterruptionMonitor { store.markInterrupted($0) }
        processes = ProcessMonitor { store.removeExitedSessions(isRunning: ProcessMonitor.isRunning) }
        alerter.onOpenSession = { [weak self] in self?.showTerminal(forSession: $0) }
        store.onAlert = { [weak self] alert in
            guard self?.shouldAlert(alert) ?? true else { return }
            alerter.handle(alert)
        }
    }

    func makeRemoteInstallCommand() async -> String {
        installer.remoteInstallCommand(code: await server.issueInstallCode())
    }

    func terminal(for session: AgentSession) -> InstalledTerminal? {
        session.terminal.flatMap(InstalledTerminal.lookup)
    }

    func showTerminal(for session: AgentSession) {
        guard let tmux = session.tmux, !session.isRemote else {
            activateTerminal(for: session)
            return
        }
        Task {
            if await InstalledTerminal.showTmuxPane(tmux) { return }
            activateTerminal(for: session)
        }
    }

    private func activateTerminal(for session: AgentSession) {
        guard !session.isRemote else {
            terminal(for: session)?.activate(tty: nil, cwd: nil)
            return
        }
        let directory = session.pid.flatMap(ProcessTree.terminalDirectory) ?? session.cwd
        terminal(for: session)?.activate(tty: session.tty, cwd: directory)
    }

    func showTerminal(forSession id: String) {
        guard let session = store.sessions.first(where: { $0.id == id }) else { return }
        showTerminal(for: session)
    }

    func start() async {
        if !hasRestored {
            hasRestored = true
            if let snapshot = persistence?.load() {
                store.restore(snapshot, isRunning: ProcessMonitor.isRunning)
            }
        }
        do {
            try await server.start()
            serverError = nil
        } catch {
            serverError = "Could not listen on 127.0.0.1:\(server.port). Is another app using the port?"
        }
        for installer in [installer, codexInstaller, antigravityInstaller] where installer.needsUpgrade {
            try? installer.install()
        }
        for installer in [statusLineInstaller, antigravityStatusLineInstaller] where installer.state == .outdated {
            try? installer.install()
        }
        refreshInstallState()
        interruptions.start()
        processes.start()
    }

    var isCodexAvailable: Bool {
        isCodexHookInstalled || FileManager.default.fileExists(atPath: codexInstaller.directory.path)
    }

    var isAntigravityAvailable: Bool {
        isAntigravityHookInstalled || FileManager.default.fileExists(atPath: antigravityInstaller.directory.deletingLastPathComponent().appending(path: "antigravity-cli").path)
    }

    func sessionsDidChange() {
        guard persistence != nil, saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: self?.saveDelay ?? .zero)
            guard !Task.isCancelled, let self else { return }
            saveTask = nil
            persistence?.save(store.snapshot())
        }
    }

    func stop() async {
        saveTask?.cancel()
        saveTask = nil
        persistence?.save(store.snapshot())
        await server.stop()
        interruptions.stop()
        processes.stop()
    }

    func refreshInstallState() {
        isHookInstalled = installer.isInstalled
        isCodexHookInstalled = codexInstaller.isInstalled
        isAntigravityHookInstalled = antigravityInstaller.isInstalled
        statusLineState = statusLineInstaller.state
        antigravityStatusLineState = antigravityStatusLineInstaller.state
        Task { [server] in
            if await !server.isListening, serverError == nil {
                serverError = "The hook server stopped listening on 127.0.0.1:\(server.port). Restart Islet."
            }
        }
    }

    var isAnyHookInstalled: Bool {
        isHookInstalled || isCodexHookInstalled || isAntigravityHookInstalled
    }

    func installHooks(for agent: AgentSession.Agent = .claudeCode) throws {
        try installer(for: agent).install()
        refreshInstallState()
    }

    func uninstallHooks(for agent: AgentSession.Agent = .claudeCode) throws {
        try installer(for: agent).uninstall()
        refreshInstallState()
    }

    func installStatusLine(for agent: AgentSession.Agent = .claudeCode) throws {
        try statusLineInstaller(for: agent).install()
        refreshInstallState()
    }

    func uninstallStatusLine(for agent: AgentSession.Agent = .claudeCode) throws {
        try statusLineInstaller(for: agent).uninstall()
        refreshInstallState()
    }

    private func statusLineInstaller(for agent: AgentSession.Agent) -> StatusLineInstaller {
        agent == .antigravity ? antigravityStatusLineInstaller : statusLineInstaller
    }

    func isHookInstalled(for agent: AgentSession.Agent) -> Bool {
        switch agent {
        case .claudeCode: isHookInstalled
        case .codex: isCodexHookInstalled
        case .antigravity: isAntigravityHookInstalled
        }
    }

    private func installer(for agent: AgentSession.Agent) -> HookInstaller {
        switch agent {
        case .claudeCode: installer
        case .codex: codexInstaller
        case .antigravity: antigravityInstaller
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
