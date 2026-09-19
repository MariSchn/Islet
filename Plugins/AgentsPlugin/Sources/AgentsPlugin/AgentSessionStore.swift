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
        apply(event)
        guard event.kind == .permissionRequest,
              let request = sessions.first(where: { $0.id == event.sessionID })?.pendingRequest,
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
        session.updatedAt = timestamp
        if event.kind != .notification, let request = session.pendingRequest {
            resolve(request.id, with: nil)
            session.pendingRequest = nil
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
            guard let toolName = event.toolName else { return }
            let request = PendingRequest(toolName: toolName, toolInput: event.toolInput)
            session.pendingRequest = request
            session.state = .needsAttention(Self.attentionReason(for: request, activity: event.activityDescription))
        case .notification:
            switch event.notificationType {
            case "permission_prompt":
                session.state = .needsAttention(event.message ?? "Needs permission")
            case "elicitation_dialog":
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
        guard let index = sessions.firstIndex(where: { $0.pendingRequest?.id == requestID }),
              let request = sessions[index].pendingRequest
        else { return }
        resolve(requestID, with: decision)
        sessions[index].pendingRequest = nil
        sessions[index].updatedAt = now()
        sessions[index].state = .working
        if decision == .deny {
            sessions[index].activity = "Denied \(request.toolName)"
        }
        onChange?()
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
        guard let index = sessions.firstIndex(where: { $0.pendingRequest?.id == requestID }) else { return }
        sessions[index].pendingRequest = nil
        onChange?()
    }

    private func withdrawPendingRequest(for sessionID: String) {
        if let request = sessions.first(where: { $0.id == sessionID })?.pendingRequest {
            resolve(request.id, with: nil)
        }
    }

    private func resolve(_ requestID: UUID, with decision: PermissionDecision?) {
        decisions.removeValue(forKey: requestID)?.resume(returning: decision)
    }

    private static func attentionReason(for request: PendingRequest, activity: String?) -> String {
        switch request.kind {
        case .permission: activity.map { "Wants to \($0)" } ?? "Needs permission"
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
