import Foundation
import IsletCore
import Observation

@MainActor
@Observable
final class AgentSessionStore {
    static let finishedPillDuration: TimeInterval = 10 * 60
    static let unreachableTimeout: TimeInterval = 5 * 60
    static let remoteExpiry: TimeInterval = 12 * 60 * 60
    static let replyTimeout = TimeInterval(HookServer.replyTimeout.components.seconds) - 10

    enum Alert: Sendable, Equatable {
        case needsAttention(AgentSession)
        case finished(AgentSession)

        var session: AgentSession {
            switch self {
            case .needsAttention(let session), .finished(let session): session
            }
        }
    }

    struct Dismissal: Sendable, Equatable, Codable {
        var pid: Int32?
        var isRemote: Bool
        var updatedAt: Date?
    }

    private(set) var sessions: [AgentSession] = []
    var onAlert: ((Alert) -> Void)?

    private let now: () -> Date
    private let localHost: () -> String
    private let lastPrompt: @Sendable (String) -> String?
    @ObservationIgnored private var dismissed: [String: Dismissal] = [:]
    private var finishedExpiries = 0
    @ObservationIgnored private var hiddenSessions: [String: AgentSession] = [:]
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var unreachableTask: Task<Void, Never>?
    @ObservationIgnored private var decisions: [UUID: CheckedContinuation<PermissionDecision?, Never>] = [:]

    convenience init(now: @escaping () -> Date = Date.init, localHost: @escaping () -> String = { AgentSessionStore.localHostName }) {
        self.init(now: now, localHost: localHost, lastPrompt: TranscriptReader.lastPrompt(at:))
    }

    init(now: @escaping () -> Date = Date.init, localHost: @escaping () -> String = { AgentSessionStore.localHostName }, lastPrompt: @escaping @Sendable (String) -> String?) {
        self.now = now
        self.localHost = localHost
        self.lastPrompt = lastPrompt
    }

    static var localHostName: String {
        var buffer = [CChar](repeating: 0, count: 256)
        gethostname(&buffer, buffer.count)
        let name = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return String(name.prefix { $0 != "." })
    }

    var orderedSessions: [AgentSession] {
        SessionOrder.sorted(sessions)
    }

    var attentionSessions: [AgentSession] {
        sessions.filter(\.state.requiresAttention)
    }

    var workingSessions: [AgentSession] {
        sessions.filter { $0.state == .working && !$0.isUnreachable }
    }

    func handle(_ event: HookEvent) async -> HookReply {
        let before = Set(sessions.first { $0.id == event.sessionID }?.pendingRequests.map(\.id) ?? [])
        let requestedAt = now()
        apply(event)
        guard event.kind == .permissionRequest,
              let request = sessions.first(where: { $0.id == event.sessionID })?.pendingRequests.first(where: { !before.contains($0.id) }),
              let decision = await awaitDecision(for: request.id, requestedAt: requestedAt)
        else { return .empty }
        return decision.reply(for: request)
    }

    func apply(_ event: HookEvent) {
        let timestamp = now()
        if event.kind == .other {
            return
        }
        if event.kind == .sessionEnd {
            dismissed[event.sessionID] = nil
            hiddenSessions[event.sessionID] = nil
            withdrawPendingRequest(for: event.sessionID)
            sessions.removeAll { $0.id == event.sessionID }
            return
        }
        if event.kind == .sessionStart, event.source == "compact" {
            return
        }
        if dismissed[event.sessionID] != nil {
            guard event.kind == .userPromptSubmit, !event.isTaskNotification else {
                dismissed[event.sessionID]?.updatedAt = timestamp
                return
            }
            dismissed[event.sessionID] = nil
        }

        let previous = sessions.first { $0.id == event.sessionID }
        var session = previous ?? hiddenSessions[event.sessionID] ?? AgentSession(
            id: event.sessionID,
            agent: event.agent,
            host: event.host,
            terminal: event.terminal,
            tty: event.tty,
            cwd: event.cwd,
            task: nil,
            activity: nil,
            state: .starting,
            startedAt: timestamp,
            turnStartedAt: timestamp,
            updatedAt: timestamp
        )
        session.agent = event.agent
        if let cwd = event.cwd { session.cwd = cwd }
        if let host = event.host {
            session.host = host
            session.isRemote = event.isFromRemoteHost || host.caseInsensitiveCompare(localHost()) != .orderedSame
        }
        session.isUnreachable = false
        if let terminal = event.terminal { session.terminal = terminal }
        if let tty = event.tty { session.tty = tty }
        if let pid = event.pid { session.pid = pid }
        if let tmux = event.tmux { session.tmux = tmux }
        if let transcriptPath = event.transcriptPath { session.transcriptPath = transcriptPath }
        if let model = event.model {
            session.model = model
            if event.agent == .codex { session.details.model = model }
            if event.agent == .antigravity, !session.hasStatusLineModel {
                session.details.model = model
                session.details.effort = event.effort
            }
        }
        if event.agent == .codex || event.agent == .antigravity, let branch = event.branch {
            session.details.branch = branch
        }
        if let title = event.title, !session.hasStatusLineTitle { session.title = title }
        session.updatedAt = timestamp
        if event.toolName == "ExitPlanMode", let plan = event.toolInput?["plan"]?.stringValue {
            session.plan = plan
        }
        let waitsForAnswerInTerminal = if case .needsAttention = session.state { session.pendingRequests.isEmpty } else { false }
        for request in Self.withdrawnRequests(session.pendingRequests, on: event) {
            resolve(request.id, with: nil)
            session.pendingRequests.removeAll { $0.id == request.id }
        }

        switch event.kind {
        case .sessionStart:
            session.state = .starting
            session.activity = nil
            session.requestsInTerminal = []
            if session.task == nil, !session.isRemote, event.source == "fork" || event.source == "resume", let path = session.transcriptPath {
                loadLastPrompt(from: path, for: session.id)
            }
        case .userPromptSubmit:
            if !event.isTaskNotification {
                session.task = event.prompt.map(Self.summarize)
                session.requestsInTerminal = []
            }
            guard session.pendingRequests.isEmpty else { break }
            session.activity = nil
            session.state = .working
            session.turnStartedAt = timestamp
        case .preToolUse, .postToolUse, .postToolUseFailure:
            session.activity = event.activityDescription
            let answeredInTerminal = event.kind != .preToolUse && Self.removeRequestInTerminal(matching: event, from: &session)
            if event.kind == .preToolUse || session.state != .interrupted, !waitsForAnswerInTerminal || event.agentID == nil || answeredInTerminal {
                session.state = .working
            }
            Self.record(event, in: &session, at: timestamp)
            if event.kind == .preToolUse, event.agent == .codex, let toolName = event.toolName, PendingRequest.codexQuestionTools.contains(toolName),
               let request = PendingRequest(toolName: toolName, toolInput: event.toolInput) {
                session.pendingRequests.removeAll { !$0.isAnswerable }
                session.pendingRequests.append(request)
            }
        case .permissionDenied:
            session.activity = event.activityDescription.map { "Denied: \($0)" } ?? "Denied a tool call"
            _ = Self.removeRequestInTerminal(matching: event, from: &session)
            Self.record(event, in: &session, at: timestamp)
        case .permissionRequest:
            let request = event.toolName.flatMap { PendingRequest(toolName: $0, toolInput: event.toolInput, agentType: event.agentType, permissionSuggestions: event.permissionSuggestions) }
            if let request, event.isInAutoMode, case .permission = request.kind {
                session.activity = event.activityDescription
                if !waitsForAnswerInTerminal || event.agentID == nil {
                    session.state = .working
                }
                session.requestsInTerminal.append(TerminalRequest(toolName: request.toolName, toolInput: request.toolInput))
            } else if let request {
                session.pendingRequests.insert(request, at: session.pendingRequests.firstIndex { !$0.isAnswerable } ?? session.pendingRequests.endIndex)
                session.state = .needsAttention(Self.attentionReason(for: session.pendingRequests[0]))
            } else {
                session.state = .needsAttention(event.activityDescription.map { "Wants to \($0)" } ?? "Needs permission")
                if let toolName = event.toolName {
                    session.requestsInTerminal.append(TerminalRequest(toolName: toolName, toolInput: event.toolInput))
                }
            }
        case .notification:
            switch event.notificationType {
            case "permission_prompt":
                guard session.pendingRequests.isEmpty else { break }
                session.state = .needsAttention(event.message ?? "Needs permission")
            case "elicitation_dialog":
                guard session.pendingRequests.isEmpty else { break }
                session.state = .needsAttention(event.message ?? "Waiting for your answer")
            case "idle_prompt":
                switch session.state {
                case .done, .interrupted, .failed: return
                case .starting, .working, .needsAttention: break
                }
                guard session.pendingRequests.isEmpty else { return }
                session.state = .needsAttention("Waiting for your input")
            default:
                return
            }
        case .stop:
            session.state = .done
            session.activity = nil
            session.requestsInTerminal = []
            session.completeOpenActivities()
        case .stopFailure:
            session.state = .failed(event.failureDescription)
            session.activity = nil
            session.requestsInTerminal = []
            session.completeOpenActivities()
        case .sessionEnd, .other:
            return
        }
        if let request = session.pendingRequests.first, !session.state.isFailed {
            session.state = .needsAttention(Self.attentionReason(for: request))
        }

        if session.agent == .claudeCode || session.agent == .antigravity, let pid = session.pid {
            let replacesAll = event.kind == .sessionStart || (session.agent == .antigravity && event.kind == .userPromptSubmit)
            let isReplaced = { (other: AgentSession) in
                other.id != session.id && other.agent == session.agent && other.pid == pid && other.host == session.host
                    && (replacesAll || (other.task == nil && other.state == .starting))
            }
            let replaced = sessions.filter(isReplaced)
            for other in replaced {
                withdrawPendingRequest(for: other.id)
            }
            sessions.removeAll { other in replaced.contains { $0.id == other.id } }
            hiddenSessions = hiddenSessions.filter { !isReplaced($0.value) }
        }
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else if Self.isActivity(event) {
            hiddenSessions[session.id] = nil
            sessions.insert(session, at: 0)
        } else {
            hiddenSessions[session.id] = session
            return
        }
        if let alert = Self.alert(from: previous?.state, to: session.state, in: session) {
            onAlert?(alert)
        }
        scheduleFinishedExpiry()
        scheduleUnreachableCheck()
    }

    private static func isActivity(_ event: HookEvent) -> Bool {
        switch event.kind {
        case .userPromptSubmit: !event.isTaskNotification
        case .preToolUse, .postToolUse, .postToolUseFailure, .permissionRequest, .permissionDenied, .stop, .stopFailure: true
        case .notification: event.notificationType == "permission_prompt" || event.notificationType == "elicitation_dialog"
        case .sessionStart, .sessionEnd, .other: false
        }
    }

    private static func alert(from previous: AgentSession.State?, to current: AgentSession.State, in session: AgentSession) -> Alert? {
        if current.requiresAttention {
            return previous?.requiresAttention == true ? nil : .needsAttention(session)
        }
        return current == .done && previous != .done ? .finished(session) : nil
    }

    func applyStatusLine(_ update: StatusLineUpdate) {
        if let index = sessions.firstIndex(where: { $0.id == update.sessionID }) {
            if let name = update.sessionName, sessions[index].title != name || !sessions[index].hasStatusLineTitle {
                sessions[index].title = name
                sessions[index].hasStatusLineTitle = true
            }
            sessions[index].details = sessions[index].details.merging(update.details)
            if update.details.model != nil { sessions[index].hasStatusLineModel = true }
        } else if var session = hiddenSessions[update.sessionID] {
            if let name = update.sessionName {
                session.title = name
                session.hasStatusLineTitle = true
            }
            session.details = session.details.merging(update.details)
            if update.details.model != nil { session.hasStatusLineModel = true }
            hiddenSessions[update.sessionID] = session
        }
    }

    func dismiss(_ id: String) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        dismissed[id] = Dismissal(pid: session.pid, isRemote: session.isRemote, updatedAt: now())
        withdrawPendingRequest(for: id)
        sessions.removeAll { $0.id == id }
    }

    func decide(_ requestID: UUID, _ decision: PermissionDecision) {
        guard let index = sessions.firstIndex(where: { $0.pendingRequests.contains { $0.id == requestID } }),
              let request = sessions[index].pendingRequests.first(where: { $0.id == requestID })
        else { return }
        resolve(requestID, with: decision)
        sessions[index].pendingRequests.removeAll { $0.id == requestID }
        sessions[index].updatedAt = now()
        switch decision {
        case .allow, .allowAlways, .answers:
            break
        case .deny:
            sessions[index].activity = "Denied \(request.toolName)"
            let digest = ActivityEntry.digest(of: request.toolInput)
            if let activity = sessions[index].activities.lastIndex(where: { !$0.isComplete && $0.toolName == request.toolName && $0.inputDigest == digest }) {
                sessions[index].activities[activity].isComplete = true
                sessions[index].activities[activity].didFail = true
            }
        }
        settleState(at: index)
        scheduleUnreachableCheck()
    }

    private func settleState(at index: Int) {
        if let next = sessions[index].pendingRequests.first {
            sessions[index].state = .needsAttention(Self.attentionReason(for: next))
        } else {
            sessions[index].state = .working
        }
    }

    private func awaitDecision(for requestID: UUID, requestedAt: Date) async -> PermissionDecision? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                decisions[requestID] = continuation
            }
        } onCancel: {
            Task { @MainActor in
                self.withdraw(requestID, timedOut: self.now().timeIntervalSince(requestedAt) >= Self.replyTimeout)
            }
        }
    }

    private func withdraw(_ requestID: UUID, timedOut: Bool) {
        resolve(requestID, with: nil)
        guard let index = sessions.firstIndex(where: { $0.pendingRequests.contains { $0.id == requestID } }) else { return }
        if timedOut, let request = sessions[index].pendingRequests.first(where: { $0.id == requestID }) {
            sessions[index].requestsInTerminal.append(TerminalRequest(toolName: request.toolName, toolInput: request.toolInput))
        }
        sessions[index].pendingRequests.removeAll { $0.id == requestID }
        if let next = sessions[index].pendingRequests.first {
            sessions[index].state = .needsAttention(Self.attentionReason(for: next))
        } else if timedOut {
            sessions[index].state = .needsAttention("Waiting for your answer in the terminal")
        } else {
            sessions[index].state = .interrupted
            sessions[index].activity = nil
            sessions[index].completeOpenActivities()
        }
        scheduleUnreachableCheck()
    }

    func handOverPendingRequests() {
        for index in sessions.indices where !sessions[index].pendingRequests.isEmpty {
            withdrawPendingRequest(for: sessions[index].id)
            sessions[index].requestsInTerminal += sessions[index].pendingRequests.map { TerminalRequest(toolName: $0.toolName, toolInput: $0.toolInput) }
            sessions[index].pendingRequests = []
            sessions[index].state = .needsAttention("Waiting for your answer in the terminal")
        }
    }

    func markInterrupted(_ sessionID: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        switch sessions[index].state {
        case .working, .needsAttention: break
        case .starting, .done, .interrupted, .failed: return
        }
        withdrawPendingRequest(for: sessionID)
        sessions[index].pendingRequests = []
        sessions[index].requestsInTerminal = []
        sessions[index].state = .interrupted
        sessions[index].activity = nil
        sessions[index].completeOpenActivities()
        sessions[index].updatedAt = now()
        scheduleUnreachableCheck()
    }

    private func loadLastPrompt(from path: String, for sessionID: String) {
        let lastPrompt = lastPrompt
        Task {
            let prompt = await Task.detached(priority: .utility) { lastPrompt(path) }.value
            guard let prompt else { return }
            if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
                guard sessions[index].task == nil else { return }
                sessions[index].task = Self.summarize(prompt)
            } else if hiddenSessions[sessionID]?.task == nil {
                hiddenSessions[sessionID]?.task = Self.summarize(prompt)
            }
        }
    }

    func snapshot() -> SessionSnapshot {
        SessionSnapshot(sessions: sessions, hiddenSessions: Array(hiddenSessions.values), dismissed: dismissed)
    }

    func restore(_ snapshot: SessionSnapshot, bootTime: Date = .distantPast, isRunning: (Int32) -> Bool) {
        let cutoff = now().addingTimeInterval(-Self.remoteExpiry)
        func isAlive(pid: Int32?, isRemote: Bool) -> Bool {
            guard !isRemote else { return true }
            guard let pid else { return false }
            return isRunning(pid)
        }
        func isAlive(_ session: AgentSession) -> Bool {
            guard session.updatedAt > (session.isRemote ? cutoff : bootTime) else { return false }
            return isAlive(pid: session.pid, isRemote: session.isRemote)
        }
        func revived(_ session: AgentSession) -> AgentSession {
            var session = session
            session.pendingRequests = []
            switch session.state {
            case .needsAttention:
                session.state = .needsAttention("Waiting for your answer in the terminal")
            case .working:
                session.state = .interrupted
                session.activity = nil
            case .starting, .done, .interrupted, .failed:
                break
            }
            return session
        }
        sessions = snapshot.sessions.filter(isAlive).map(revived)
        hiddenSessions = Dictionary(snapshot.hiddenSessions.filter(isAlive).map { ($0.id, revived($0)) }, uniquingKeysWith: { first, _ in first })
        dismissed = (snapshot.dismissed ?? [:])
            .filter { isAlive(pid: $0.value.pid, isRemote: $0.value.isRemote) }
            .mapValues { dismissal in
                var dismissal = dismissal
                dismissal.updatedAt = dismissal.updatedAt ?? now()
                return dismissal
            }
        scheduleFinishedExpiry()
        scheduleUnreachableCheck()
    }

    func removeExitedSessions(isRunning: (Int32) -> Bool) {
        let cutoff = now().addingTimeInterval(-Self.remoteExpiry)
        hiddenSessions = hiddenSessions.filter { _, session in
            guard !session.isRemote, let pid = session.pid else { return session.updatedAt > cutoff }
            return isRunning(pid)
        }
        dismissed = dismissed.filter { _, dismissal in
            guard !dismissal.isRemote, let pid = dismissal.pid else { return (dismissal.updatedAt ?? .distantPast) > cutoff }
            return isRunning(pid)
        }
        let exited = sessions.filter { session in
            if session.isRemote { return session.updatedAt <= cutoff && !session.state.requiresAttention }
            guard let pid = session.pid else { return false }
            return !isRunning(pid)
        }
        guard !exited.isEmpty else { return }
        for session in exited {
            withdrawPendingRequest(for: session.id)
        }
        sessions.removeAll { session in exited.contains { $0.id == session.id } }
    }

    private static func input(_ requested: JSONValue?, isContainedIn actual: JSONValue?) -> Bool {
        guard case .object(let requestedFields)? = requested, case .object(let actualFields)? = actual else {
            return requested == actual
        }
        return requestedFields.allSatisfy { actualFields[$0.key] == $0.value }
    }

    private static func removeRequestInTerminal(matching event: HookEvent, from session: inout AgentSession) -> Bool {
        guard let index = session.requestsInTerminal.firstIndex(where: { $0.toolName == event.toolName && input($0.toolInput, isContainedIn: event.toolInput) }) else { return false }
        session.requestsInTerminal.remove(at: index)
        return true
    }

    private func withdrawPendingRequest(for sessionID: String) {
        for request in sessions.first(where: { $0.id == sessionID })?.pendingRequests ?? [] {
            resolve(request.id, with: nil)
        }
    }

    private static func record(_ event: HookEvent, in session: inout AgentSession, at timestamp: Date) {
        let didFail = event.kind == .postToolUseFailure || event.kind == .permissionDenied
        let digest = ActivityEntry.digest(of: event.toolInput)
        if event.kind != .preToolUse, let index = session.activities.lastIndex(where: { !$0.isComplete && $0.toolName == event.toolName && $0.inputDigest == digest }) {
            session.activities[index].isComplete = true
            session.activities[index].didFail = didFail
            return
        }
        session.activities.append(ActivityEntry(event: event, at: timestamp, isComplete: event.kind != .preToolUse, didFail: didFail))
        if session.activities.count > ActivityEntry.limit {
            session.activities.removeFirst(session.activities.count - ActivityEntry.limit)
        }
    }

    private static func withdrawnRequests(_ requests: [PendingRequest], on event: HookEvent) -> [PendingRequest] {
        switch event.kind {
        case .sessionStart, .sessionEnd:
            return requests
        case .stop, .stopFailure:
            return requests.filter(\.isAnswerable)
        case .userPromptSubmit:
            return event.isTaskNotification ? [] : requests
        case .postToolUse, .postToolUseFailure:
            let sameTool = requests.filter { ($0.isAnswerable || $0.toolName == "request_user_input") && $0.toolName == event.toolName }
            let match = sameTool.first { $0.toolInput == event.toolInput }
                ?? sameTool.first { input($0.toolInput, isContainedIn: event.toolInput) }
                ?? sameTool.first { $0.isQuestion && $0.agentType == event.agentType }
            return match.map { [$0] } ?? []
        case .preToolUse:
            guard event.agentType == nil, let toolName = event.toolName, toolName != "AskUserQuestion" else { return [] }
            return requests.filter { $0.isQuestion && $0.isAnswerable && $0.agentType == nil }
        case .permissionRequest, .permissionDenied, .notification, .other:
            return []
        }
    }

    private func resolve(_ requestID: UUID, with decision: PermissionDecision?) {
        decisions.removeValue(forKey: requestID)?.resume(returning: decision)
    }

    private static func attentionReason(for request: PendingRequest) -> String {
        switch request.kind {
        case .permission(let tool, _): request.activityDescription.map { "Wants to \($0)" } ?? "Wants to use \(tool)"
        case .question(let questions): questions.count == 1 ? "Has a question" : "Has \(questions.count) questions"
        }
    }

    func pillStatus(for display: DisplaySettings) -> PillStatus? {
        let ring = display.pillContent == .ring ? statusRing(keepingFinishedSessions: display.ringKeepsFinishedSessions) : nil
        let attention = attentionSessions
        if let first = attention.first {
            let text = attention.count == 1 ? "\(first.displayName) needs you" : "\(attention.count) agents need you"
            return PillStatus(text: text, systemImage: "terminal.fill", priority: .attention, ring: ring)
        }
        let working = workingSessions
        if display.pillShowsWorking, !working.isEmpty {
            let text = working.count == 1 ? (working[0].activity ?? working[0].displayName) : "\(working.count) agents working"
            return PillStatus(text: text, systemImage: "terminal", priority: .info, ring: ring)
        }
        let finished = recentlyFinishedSessions
        guard display.pillShowsFinished, let first = finished.first else { return nil }
        let text = finished.count == 1 ? "\(first.displayName) finished" : "\(finished.count) agents finished"
        return PillStatus(text: text, systemImage: "checkmark.circle.fill", priority: .ambient, ring: ring)
    }

    func statusRing(keepingFinishedSessions: Bool) -> PillStatus.Ring {
        let cutoff = keepingFinishedSessions ? .distantPast : finishedCutoff
        var counts = (attention: 0, working: 0, finished: 0, idle: 0)
        for session in sessions {
            switch session.state {
            case .needsAttention, .failed: counts.attention += 1
            case .working where !session.isUnreachable: counts.working += 1
            case .done where session.updatedAt > cutoff: counts.finished += 1
            case .starting, .working, .done, .interrupted: counts.idle += 1
            }
        }
        return PillStatus.Ring(segments: [
            .init(value: Double(counts.attention), tint: SessionColors.attentionTint),
            .init(value: Double(counts.working), tint: SessionColors.workingTint),
            .init(value: Double(counts.finished), tint: SessionColors.finishedTint),
            .init(value: Double(counts.idle), tint: SessionColors.idleTint),
        ].filter { $0.value > 0 })
    }

    private var finishedCutoff: Date {
        _ = finishedExpiries
        return now().addingTimeInterval(-Self.finishedPillDuration)
    }

    private var recentlyFinishedSessions: [AgentSession] {
        let cutoff = finishedCutoff
        return sessions.filter { $0.state == .done && $0.updatedAt > cutoff }
    }

    private func scheduleFinishedExpiry() {
        expiryTask?.cancel()
        guard let oldest = recentlyFinishedSessions.map(\.updatedAt).min() else { return }
        let delay = oldest.addingTimeInterval(Self.finishedPillDuration).timeIntervalSince(now())
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(delay, 0) + 1))
            guard !Task.isCancelled else { return }
            self?.finishedExpiries += 1
            self?.scheduleFinishedExpiry()
        }
    }

    private var reachabilityCandidates: [AgentSession] {
        sessions.filter { $0.isRemote && $0.state == .working && !$0.isUnreachable }
    }

    private func scheduleUnreachableCheck() {
        unreachableTask?.cancel()
        guard let oldest = reachabilityCandidates.map(\.updatedAt).min() else { return }
        let delay = oldest.addingTimeInterval(Self.unreachableTimeout).timeIntervalSince(now())
        unreachableTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(delay, 0) + 1))
            guard !Task.isCancelled else { return }
            self?.markUnreachableSessions()
        }
    }

    func markUnreachableSessions() {
        let cutoff = now().addingTimeInterval(-Self.unreachableTimeout)
        for index in sessions.indices where sessions[index].isRemote && sessions[index].state == .working && !sessions[index].isUnreachable && sessions[index].updatedAt <= cutoff {
            sessions[index].isUnreachable = true
        }
        scheduleUnreachableCheck()
    }

    static func summarize(_ prompt: String) -> String {
        let firstLine = prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? prompt
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 80 ? String(trimmed.prefix(79)) + "…" : trimmed
    }
}
