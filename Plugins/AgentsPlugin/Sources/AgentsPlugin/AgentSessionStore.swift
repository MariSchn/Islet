import Foundation
import IsletCore
import Observation

@MainActor
@Observable
public final class AgentSessionStore {
    public static let finishedPillDuration: TimeInterval = 10 * 60
    public static let unreachableTimeout: TimeInterval = 5 * 60
    static let replyTimeout = TimeInterval(HookServer.replyTimeout.components.seconds) - 10

    public enum Alert: Sendable, Equatable {
        case needsAttention(AgentSession)
        case finished(AgentSession)
    }

    public private(set) var sessions: [AgentSession] = []
    public var onChange: (() -> Void)?
    public var onAlert: ((Alert) -> Void)?

    private let now: () -> Date
    private let localHost: () -> String
    private let lastPrompt: @Sendable (String) -> String?
    private var dismissedIDs: Set<String> = []
    @ObservationIgnored private var hiddenSessions: [String: AgentSession] = [:]
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var unreachableTask: Task<Void, Never>?
    @ObservationIgnored private var decisions: [UUID: CheckedContinuation<PermissionDecision?, Never>] = [:]

    public convenience init(now: @escaping () -> Date = Date.init, localHost: @escaping () -> String = { AgentSessionStore.localHostName }) {
        self.init(now: now, localHost: localHost, lastPrompt: TranscriptReader.lastPrompt(at:))
    }

    init(now: @escaping () -> Date = Date.init, localHost: @escaping () -> String = { AgentSessionStore.localHostName }, lastPrompt: @escaping @Sendable (String) -> String?) {
        self.now = now
        self.localHost = localHost
        self.lastPrompt = lastPrompt
    }

    public static var localHostName: String {
        var buffer = [CChar](repeating: 0, count: 256)
        gethostname(&buffer, buffer.count)
        return String(String(cString: buffer).prefix { $0 != "." })
    }

    public var attentionSessions: [AgentSession] {
        sessions.filter(\.state.requiresAttention)
    }

    public var workingSessions: [AgentSession] {
        sessions.filter { $0.state == .working && !$0.isUnreachable }
    }

    public func handle(_ event: HookEvent) async -> HookReply {
        let before = Set(sessions.first { $0.id == event.sessionID }?.pendingRequests.map(\.id) ?? [])
        let requestedAt = now()
        apply(event)
        guard event.kind == .permissionRequest,
              let request = sessions.first(where: { $0.id == event.sessionID })?.pendingRequests.first(where: { !before.contains($0.id) }),
              let decision = await awaitDecision(for: request.id, requestedAt: requestedAt)
        else { return .empty }
        return decision.reply(for: request)
    }

    public func apply(_ event: HookEvent) {
        let timestamp = now()
        if event.kind == .sessionEnd {
            dismissedIDs.remove(event.sessionID)
            hiddenSessions[event.sessionID] = nil
            withdrawPendingRequest(for: event.sessionID)
            sessions.removeAll { $0.id == event.sessionID }
            onChange?()
            return
        }
        if event.kind == .sessionStart, event.source == "compact" {
            return
        }
        if dismissedIDs.contains(event.sessionID) {
            guard event.kind == .userPromptSubmit, !event.isTaskNotification else { return }
            dismissedIDs.remove(event.sessionID)
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
            session.isRemote = host.caseInsensitiveCompare(localHost()) != .orderedSame
        }
        session.isUnreachable = false
        if let terminal = event.terminal { session.terminal = terminal }
        if let tty = event.tty { session.tty = tty }
        if let pid = event.pid { session.pid = pid }
        if let transcriptPath = event.transcriptPath { session.transcriptPath = transcriptPath }
        if let title = event.title { session.title = title }
        session.updatedAt = timestamp
        if event.toolName == "ExitPlanMode", let plan = event.toolInput?["plan"]?.stringValue {
            session.plan = plan
        }
        for request in Self.withdrawnRequests(session.pendingRequests, on: event) {
            resolve(request.id, with: nil)
            session.pendingRequests.removeAll { $0.id == request.id }
        }

        switch event.kind {
        case .sessionStart:
            session.state = .starting
            session.activity = nil
            if session.task == nil, !session.isRemote, event.source == "fork" || event.source == "resume", let path = session.transcriptPath {
                loadLastPrompt(from: path, for: session.id)
            }
        case .userPromptSubmit:
            if !event.isTaskNotification {
                session.task = event.prompt.map(Self.summarize)
            }
            guard session.pendingRequests.isEmpty else { break }
            session.activity = nil
            session.state = .working
            session.turnStartedAt = timestamp
        case .preToolUse, .postToolUse:
            session.activity = event.activityDescription
            if event.kind == .preToolUse || session.state != .interrupted {
                session.state = .working
            }
            Self.record(event, in: &session, at: timestamp)
        case .permissionRequest:
            let request = event.toolName.flatMap { PendingRequest(toolName: $0, toolInput: event.toolInput, agentType: event.agentType) }
            if let request, event.isInAutoMode, case .permission = request.kind {
                session.activity = event.activityDescription
                session.state = .working
            } else if let request {
                session.pendingRequests.append(request)
                session.state = .needsAttention(Self.attentionReason(for: session.pendingRequests[0]))
            } else {
                session.state = .needsAttention(event.activityDescription.map { "Wants to \($0)" } ?? "Needs permission")
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
                guard session.state != .done, session.state != .interrupted, session.pendingRequests.isEmpty else { return }
                session.state = .needsAttention("Waiting for your input")
            default:
                return
            }
        case .stop:
            session.state = .done
            session.activity = nil
        case .sessionEnd:
            return
        }

        var replacedVisibleSession = false
        if session.agent == .claudeCode, let pid = session.pid {
            let replacesAll = event.kind == .sessionStart
            let isReplaced = { (other: AgentSession) in
                other.id != session.id && other.agent == .claudeCode && other.pid == pid && other.host == session.host
                    && (replacesAll || (other.task == nil && other.state == .starting))
            }
            let replaced = sessions.filter(isReplaced)
            for other in replaced {
                withdrawPendingRequest(for: other.id)
            }
            sessions.removeAll { other in replaced.contains { $0.id == other.id } }
            hiddenSessions = hiddenSessions.filter { !isReplaced($0.value) }
            replacedVisibleSession = !replaced.isEmpty
        }
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else if Self.isActivity(event) {
            hiddenSessions[session.id] = nil
            sessions.insert(session, at: 0)
        } else {
            hiddenSessions[session.id] = session
            if replacedVisibleSession { onChange?() }
            return
        }
        onChange?()
        if let alert = Self.alert(from: previous?.state, to: session.state, in: session) {
            onAlert?(alert)
        }
        scheduleFinishedExpiry()
        scheduleUnreachableCheck()
    }

    private static func isActivity(_ event: HookEvent) -> Bool {
        switch event.kind {
        case .userPromptSubmit: !event.isTaskNotification
        case .preToolUse, .postToolUse, .permissionRequest, .stop: true
        case .notification: event.notificationType == "permission_prompt" || event.notificationType == "elicitation_dialog"
        case .sessionStart, .sessionEnd: false
        }
    }

    private static func alert(from previous: AgentSession.State?, to current: AgentSession.State, in session: AgentSession) -> Alert? {
        switch current {
        case .needsAttention where previous?.requiresAttention != true: .needsAttention(session)
        case .done where previous != .done: .finished(session)
        default: nil
        }
    }

    public func dismiss(_ id: String) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        dismissedIDs.insert(id)
        withdrawPendingRequest(for: id)
        sessions.removeAll { $0.id == id }
        onChange?()
    }

    public func decide(_ requestID: UUID, _ decision: PermissionDecision) {
        guard let index = sessions.firstIndex(where: { $0.pendingRequests.contains { $0.id == requestID } }),
              let request = sessions[index].pendingRequests.first(where: { $0.id == requestID })
        else { return }
        resolve(requestID, with: decision)
        sessions[index].pendingRequests.removeAll { $0.id == requestID }
        sessions[index].updatedAt = now()
        if decision == .deny {
            sessions[index].activity = "Denied \(request.toolName)"
        }
        settleState(at: index)
        onChange?()
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
        sessions[index].pendingRequests.removeAll { $0.id == requestID }
        if let next = sessions[index].pendingRequests.first {
            sessions[index].state = .needsAttention(Self.attentionReason(for: next))
        } else if timedOut {
            sessions[index].state = .needsAttention("Waiting for your answer in the terminal")
        } else {
            sessions[index].state = .interrupted
            sessions[index].activity = nil
        }
        onChange?()
    }

    public func markInterrupted(_ sessionID: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        switch sessions[index].state {
        case .working, .needsAttention: break
        case .starting, .done, .interrupted: return
        }
        withdrawPendingRequest(for: sessionID)
        sessions[index].pendingRequests = []
        sessions[index].state = .interrupted
        sessions[index].activity = nil
        sessions[index].updatedAt = now()
        onChange?()
    }

    private func loadLastPrompt(from path: String, for sessionID: String) {
        let lastPrompt = lastPrompt
        Task {
            let prompt = await Task.detached(priority: .utility) { lastPrompt(path) }.value
            guard let prompt else { return }
            if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
                guard sessions[index].task == nil else { return }
                sessions[index].task = Self.summarize(prompt)
                onChange?()
            } else if hiddenSessions[sessionID]?.task == nil {
                hiddenSessions[sessionID]?.task = Self.summarize(prompt)
            }
        }
    }

    func removeExitedSessions(isRunning: (Int32) -> Bool) {
        hiddenSessions = hiddenSessions.filter { _, session in
            guard !session.isRemote, let pid = session.pid else { return true }
            return isRunning(pid)
        }
        let exited = sessions.filter { session in
            guard !session.isRemote, let pid = session.pid else { return false }
            return !isRunning(pid)
        }
        guard !exited.isEmpty else { return }
        for session in exited {
            withdrawPendingRequest(for: session.id)
        }
        sessions.removeAll { session in exited.contains { $0.id == session.id } }
        onChange?()
    }

    private static func input(_ requested: JSONValue?, isContainedIn actual: JSONValue?) -> Bool {
        guard case .object(let requestedFields)? = requested, case .object(let actualFields)? = actual else {
            return requested == actual
        }
        return requestedFields.allSatisfy { actualFields[$0.key] == $0.value }
    }

    private func withdrawPendingRequest(for sessionID: String) {
        for request in sessions.first(where: { $0.id == sessionID })?.pendingRequests ?? [] {
            resolve(request.id, with: nil)
        }
    }

    private static func record(_ event: HookEvent, in session: inout AgentSession, at timestamp: Date) {
        if event.kind == .postToolUse, let index = session.activities.lastIndex(where: { !$0.isComplete && $0.matches(event) }) {
            session.activities[index].isComplete = true
            return
        }
        session.activities.append(ActivityEntry(event: event, at: timestamp, isComplete: event.kind == .postToolUse))
        if session.activities.count > ActivityEntry.limit {
            session.activities.removeFirst(session.activities.count - ActivityEntry.limit)
        }
    }

    private static func withdrawnRequests(_ requests: [PendingRequest], on event: HookEvent) -> [PendingRequest] {
        switch event.kind {
        case .stop, .sessionStart, .sessionEnd:
            return requests
        case .userPromptSubmit:
            return event.isTaskNotification ? [] : requests
        case .postToolUse:
            let sameTool = requests.filter { $0.toolName == event.toolName }
            let match = sameTool.first { $0.toolInput == event.toolInput }
                ?? sameTool.first { input($0.toolInput, isContainedIn: event.toolInput) }
                ?? sameTool.first { $0.isQuestion && $0.agentType == event.agentType }
            return match.map { [$0] } ?? []
        case .preToolUse:
            guard event.agentType == nil, let toolName = event.toolName, toolName != "AskUserQuestion" else { return [] }
            return requests.filter { $0.isQuestion && $0.agentType == nil }
        case .permissionRequest, .notification:
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

    public var pillStatus: PillStatus? {
        let attention = attentionSessions
        if let first = attention.first {
            let text = attention.count == 1 ? "\(first.displayName) needs you" : "\(attention.count) agents need you"
            return PillStatus(text: text, systemImage: "terminal.fill", priority: .attention, ring: statusRing)
        }
        let working = workingSessions
        if !working.isEmpty {
            let text = working.count == 1 ? (working[0].activity ?? working[0].displayName) : "\(working.count) agents working"
            return PillStatus(text: text, systemImage: "terminal", priority: .info, ring: statusRing)
        }
        let finished = recentlyFinishedSessions
        guard let first = finished.first else { return nil }
        let text = finished.count == 1 ? "\(first.displayName) finished" : "\(finished.count) agents finished"
        return PillStatus(text: text, systemImage: "checkmark.circle.fill", priority: .info, ring: statusRing)
    }

    public var statusRing: PillStatus.Ring {
        let finishedCutoff = now().addingTimeInterval(-Self.finishedPillDuration)
        var counts = (attention: 0, working: 0, finished: 0, idle: 0)
        for session in sessions {
            switch session.state {
            case .needsAttention: counts.attention += 1
            case .working where !session.isUnreachable: counts.working += 1
            case .done where session.updatedAt > finishedCutoff: counts.finished += 1
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

    private var recentlyFinishedSessions: [AgentSession] {
        let cutoff = now().addingTimeInterval(-Self.finishedPillDuration)
        return sessions.filter { $0.state == .done && $0.updatedAt > cutoff }
    }

    private func scheduleFinishedExpiry() {
        expiryTask?.cancel()
        guard let oldest = recentlyFinishedSessions.map(\.updatedAt).min() else { return }
        let delay = oldest.addingTimeInterval(Self.finishedPillDuration).timeIntervalSince(now())
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(delay, 0) + 1))
            guard !Task.isCancelled else { return }
            self?.onChange?()
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

    public func markUnreachableSessions() {
        let cutoff = now().addingTimeInterval(-Self.unreachableTimeout)
        var changed = false
        for index in sessions.indices where sessions[index].isRemote && sessions[index].state == .working && !sessions[index].isUnreachable && sessions[index].updatedAt <= cutoff {
            sessions[index].isUnreachable = true
            changed = true
        }
        if changed { onChange?() }
        scheduleUnreachableCheck()
    }

    static func summarize(_ prompt: String) -> String {
        let firstLine = prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? prompt
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 80 ? String(trimmed.prefix(79)) + "…" : trimmed
    }
}
