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

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    public var attentionSessions: [AgentSession] {
        sessions.filter(\.state.requiresAttention)
    }

    public var workingSessions: [AgentSession] {
        sessions.filter { $0.state == .working }
    }

    public func apply(_ event: HookEvent) {
        let timestamp = now()
        if event.kind == .sessionEnd {
            dismissedIDs.remove(event.sessionID)
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
            session.state = .needsAttention(event.activityDescription.map { "Wants to \($0)" } ?? "Needs permission")
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
        sessions.removeAll { $0.id == id }
        onChange?()
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
