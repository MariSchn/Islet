import Foundation
import IsletCore
import Observation
import os

@MainActor
@Observable
final class AgentsController {
    let store: AgentSessionStore
    let port: UInt16
    private(set) var installedHooks: Set<AgentSession.Agent> = []
    private(set) var statusLineStates: [AgentSession.Agent: StatusLineInstaller.State] = [:]
    private(set) var serverError: String?
    private(set) var remoteToken: String
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
        if !expandedSessionIDs.isSubset(of: ids) {
            expandedSessionIDs.formIntersection(ids)
        }
    }

    var display: DisplaySettings
    var alerts: AlertSettings {
        didSet { alerter.settings = alerts }
    }

    let interruptions: InterruptionMonitor
    private let processes: ProcessMonitor
    private let home: URL
    private let token: String
    private let server: HookServer
    private let alerter: SessionAlerter
    private let persistence: SessionPersistence?
    private let saveDelay: Duration
    private var saveTask: Task<Void, Never>?
    private var hasRestored = false
    @ObservationIgnored private var announcer = StatusAnnouncer()
    @ObservationIgnored private var contextAlert = ContextAlert()
    @ObservationIgnored private var reviewAlert = ReviewAlert()

    init(token: String, remoteToken: String = HookServer.makeToken(), home: URL, port: UInt16 = HookServer.defaultPort, alerts: AlertSettings = AlertSettings(), display: DisplaySettings = DisplaySettings(), showsUsage: Bool = false, usage: UsageMonitor? = nil, storageDirectory: URL? = nil, saveDelay: Duration = .seconds(1), logger: Logger = Logger()) {
        persistence = storageDirectory.map { SessionPersistence(directory: $0, logger: logger) }
        self.saveDelay = saveDelay
        let store = AgentSessionStore()
        self.store = store
        self.usage = usage ?? UsageMonitor(isEnabled: showsUsage)
        self.home = home
        self.port = port
        self.token = token
        self.remoteToken = remoteToken
        let usage = self.usage
        server = HookServer(port: port, token: token, remoteToken: remoteToken, installScript: Self.remoteInstallScript(port: port, token: remoteToken)) { update in
            logger.debug("Status line update for \(update.sessionID, privacy: .public): 5h \(update.usage?.fiveHour.map { "\($0.utilization)%" } ?? "absent", privacy: .public), 7d \(update.usage?.sevenDay.map { "\($0.utilization)%" } ?? "absent", privacy: .public)")
            await store.applyStatusLine(update)
            if let limits = update.usage {
                await usage.receive(limits)
            }
            if let quota = update.antigravityQuota {
                await usage.receive(quota)
            }
            if !update.isAntigravity, let cost = update.details.costUSD {
                await usage.record(sessionID: update.sessionID, cost: cost, sessionDuration: update.details.duration)
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
        readInstallState()
    }

    func hookInstaller(for agent: AgentSession.Agent) -> HookInstaller {
        HookInstaller(agent: agent, home: home, port: port, token: token)
    }

    func statusLineInstaller(for agent: AgentSession.Agent) -> StatusLineInstaller? {
        StatusLineInstaller(agent: agent, home: home, port: port, token: token)
    }

    var sshConfigSnippet: String {
        hookInstaller(for: .claudeCode).sshConfigSnippet
    }

    static func remoteInstallScript(port: UInt16, token: String) -> String {
        HookInstaller.remoteInstallScript(for: [.claudeCode, .codex].map { HookInstaller(agent: $0, home: URL(filePath: "/"), port: port, token: token) })
    }

    var remoteInstallCommandPreview: String {
        hookInstaller(for: .claudeCode).remoteInstallCommand(code: "<one-time code>", scriptHash: "<hash>")
    }

    func makeRemoteInstallCommand() async -> String {
        let code = await server.issueInstallCode()
        return hookInstaller(for: .claudeCode).remoteInstallCommand(code: code, scriptHash: await server.installScriptHash ?? "")
    }

    func resetRemoteAccess() async {
        let token = HookServer.makeToken()
        remoteToken = token
        await server.setRemoteAccess(token: token, installScript: Self.remoteInstallScript(port: port, token: token))
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
                store.restore(snapshot, bootTime: ProcessMonitor.bootTime, isRunning: ProcessMonitor.isRunning)
                if let costs = snapshot.costs { usage.restore(costs) }
                _ = announcements(for: store.sessions)
            }
        }
        do {
            try await server.start()
            serverError = nil
        } catch {
            serverError = "Could not listen on 127.0.0.1:\(server.port). Is another app using the port?"
        }
        for agent in AgentSession.Agent.allCases {
            let hooks = hookInstaller(for: agent)
            if hooks.needsUpgrade { try? hooks.install() }
            if let statusLine = statusLineInstaller(for: agent), statusLine.state == .outdated { try? statusLine.install() }
        }
        refreshInstallState()
        interruptions.start()
        interruptions.track(store.sessions)
        processes.start()
    }

    func isAvailable(_ agent: AgentSession.Agent) -> Bool {
        guard let path = agent.installationPath else { return true }
        return installedHooks.contains(agent) || FileManager.default.fileExists(atPath: home.appending(path: path).path)
    }

    var availableAgents: [AgentSession.Agent] {
        AgentSession.Agent.allCases.filter(isAvailable)
    }

    @discardableResult
    func sessionsDidChange() -> PillAnnouncement? {
        pruneMutedSessions()
        alerter.withdrawResolvedNotifications(for: store.sessions)
        let announcement = announcements(for: store.sessions).max { $0.priority < $1.priority }
        interruptions.track(store.sessions)
        scheduleSave()
        return announcement
    }

    private func announcements(for sessions: [AgentSession]) -> [PillAnnouncement] {
        var announcements: [PillAnnouncement] = []
        if let announcement = announcer.announcement(for: sessions, muted: mutedSessionIDs), shouldAnnounce(announcement) {
            announcements.append(announcement)
        }
        let details = contextAlert.announcements(for: sessions, muted: mutedSessionIDs) + reviewAlert.announcements(for: sessions, muted: mutedSessionIDs)
        if alerts.announcesInNotch {
            announcements += details
        }
        return announcements
    }

    private func scheduleSave() {
        guard persistence != nil, saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: self?.saveDelay ?? .zero)
            guard !Task.isCancelled, let self else { return }
            saveTask = nil
            persistence?.save(snapshot())
        }
    }

    private func snapshot() -> SessionSnapshot {
        var snapshot = store.snapshot()
        snapshot.costs = usage.costs
        return snapshot
    }

    func stop() async {
        saveTask?.cancel()
        saveTask = nil
        store.handOverPendingRequests()
        persistence?.save(snapshot())
        await server.stop()
        interruptions.stop()
        processes.stop()
    }

    func refreshInstallState() {
        readInstallState()
        Task { [server] in
            if await !server.isListening, serverError == nil {
                serverError = "The hook server stopped listening on 127.0.0.1:\(server.port). Restart Islet."
            }
        }
    }

    private func readInstallState() {
        installedHooks = Set(AgentSession.Agent.allCases.filter { hookInstaller(for: $0).isInstalled })
        statusLineStates = AgentSession.Agent.allCases.reduce(into: [:]) { states, agent in
            states[agent] = statusLineInstaller(for: agent)?.state
        }
    }

    func installHooks(for agent: AgentSession.Agent) throws {
        try hookInstaller(for: agent).install()
        refreshInstallState()
    }

    func toggleHooks(for agent: AgentSession.Agent) throws {
        let installer = hookInstaller(for: agent)
        try installedHooks.contains(agent) ? installer.uninstall() : installer.install()
        refreshInstallState()
    }

    func toggleStatusLine(for agent: AgentSession.Agent) throws {
        guard let installer = statusLineInstaller(for: agent) else { return }
        switch statusLineStates[agent] {
        case .installed, .outdated: try installer.uninstall()
        case .notInstalled, .replaced, nil: try installer.install()
        }
        refreshInstallState()
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
