import Foundation
import IsletCore
import Observation

@MainActor
@Observable
public final class AgentSessionStore {
    public static let finishedPillDuration: TimeInterval = 10 * 60

    public private(set) var sessions: [AgentSession] = []
    public var onChange: (() -> Void)?

    private let now: () -> Date
    private var dismissedIDs: Set<String> = []
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var decisions: [UUID: CheckedContinuation<PermissionDecision?, Never>] = [:]

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    public var attentionSessions: [AgentSession] {
        sessions.filter(\.state.requiresAttention)
    }

    public var workingSessions: [AgentSession] {
        sessions.filter { $0.state == .working }
    }

    public func handle(_ event: HookEvent) async -> HookReply {
        let before = Set(sessions.first { $0.id == event.sessionID }?.pendingRequests.map(\.id) ?? [])
        apply(event)
        guard event.kind == .permissionRequest,
              let request = sessions.first(where: { $0.id == event.sessionID })?.pendingRequests.first(where: { !before.contains($0.id) }),
              let decision = await awaitDecision(for: request.id)
        else { return .empty }
        return decision.reply(for: request)
    }

    public func apply(_ event: HookEvent) {
        let timestamp = now()
        if event.kind == .sessionEnd {
            dismissedIDs.remove(event.sessionID)
            withdrawPendingRequest(for: event.sessionID)
            sessions.removeAll { $0.id == event.sessionID }
            onChange?()
            return
        }
        if event.kind == .sessionStart, event.source == "compact" {
            return
        }
        if dismissedIDs.contains(event.sessionID) {
            guard event.kind == .userPromptSubmit else { return }
            dismissedIDs.remove(event.sessionID)
        }

        var session = sessions.first { $0.id == event.sessionID } ?? AgentSession(
            id: event.sessionID,
            agent: .claudeCode,
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
        if let cwd = event.cwd { session.cwd = cwd }
        if let host = event.host { session.host = host }
        if let terminal = event.terminal { session.terminal = terminal }
        if let tty = event.tty { session.tty = tty }
        session.updatedAt = timestamp
        for request in session.pendingRequests where Self.withdraws(request, on: event) {
            resolve(request.id, with: nil)
            session.pendingRequests.removeAll { $0.id == request.id }
        }

        switch event.kind {
        case .sessionStart:
            session.state = .starting
            session.activity = nil
        case .userPromptSubmit:
            session.task = event.prompt.map(Self.summarize)
            session.activity = nil
            session.state = .working
            session.turnStartedAt = timestamp
        case .preToolUse, .postToolUse:
            session.activity = event.activityDescription
            session.state = .working
        case .permissionRequest:
            if let toolName = event.toolName, let request = PendingRequest(toolName: toolName, toolInput: event.toolInput) {
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
                guard session.state != .done else { return }
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

        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        onChange?()
        scheduleFinishedExpiry()
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

    private func awaitDecision(for requestID: UUID) async -> PermissionDecision? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                decisions[requestID] = continuation
            }
        } onCancel: {
            Task { @MainActor in self.withdraw(requestID) }
        }
    }

    private func withdraw(_ requestID: UUID) {
        resolve(requestID, with: nil)
        guard let index = sessions.firstIndex(where: { $0.pendingRequests.contains { $0.id == requestID } }) else { return }
        sessions[index].pendingRequests.removeAll { $0.id == requestID }
        settleState(at: index)
        onChange?()
    }

    private func withdrawPendingRequest(for sessionID: String) {
        for request in sessions.first(where: { $0.id == sessionID })?.pendingRequests ?? [] {
            resolve(request.id, with: nil)
        }
    }

    private static func withdraws(_ request: PendingRequest, on event: HookEvent) -> Bool {
        switch event.kind {
        case .userPromptSubmit, .stop, .sessionStart, .sessionEnd: true
        case .postToolUse: event.toolName == request.toolName && event.toolInput == request.toolInput
        case .preToolUse, .permissionRequest, .notification: false
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
            let text = attention.count == 1 ? "\(first.projectName) needs you" : "\(attention.count) agents need you"
            return PillStatus(text: text, systemImage: "terminal.fill", priority: .attention)
        }
        let working = workingSessions
        if !working.isEmpty {
            let text = working.count == 1 ? (working[0].activity ?? working[0].projectName) : "\(working.count) agents working"
            return PillStatus(text: text, systemImage: "terminal", priority: .info)
        }
        let finished = recentlyFinishedSessions
        guard let first = finished.first else { return nil }
        let text = finished.count == 1 ? "\(first.projectName) finished" : "\(finished.count) agents finished"
        return PillStatus(text: text, systemImage: "checkmark.circle.fill", priority: .info)
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

    static func summarize(_ prompt: String) -> String {
        let firstLine = prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? prompt
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 80 ? String(trimmed.prefix(79)) + "…" : trimmed
    }
}
