import Foundation
import IsletCore
import Observation

@MainActor
@Observable
public final class AgentSessionStore {
    public private(set) var sessions: [AgentSession] = []
    public var onChange: (() -> Void)?

    private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    public var attentionSessions: [AgentSession] {
        sessions.filter(\.state.needsAttention)
    }

    public var workingSessions: [AgentSession] {
        sessions.filter { $0.state == .working }
    }

    public func apply(_ event: HookEvent) {
        let timestamp = now()
        if event.kind == .sessionEnd {
            sessions.removeAll { $0.id == event.sessionID }
            onChange?()
            return
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
        case .preToolUse, .postToolUse:
            session.activity = event.activityDescription
            session.state = .working
        case .permissionRequest:
            session.state = .needsAttention(event.activityDescription.map { "Wants to \($0)" } ?? "Needs permission")
        case .notification:
            switch event.notificationType {
            case "permission_prompt":
                session.state = .needsAttention(event.message ?? "Needs permission")
            case "idle_prompt":
                session.state = .needsAttention("Waiting for your input")
            default:
                if let message = event.message { session.state = .needsAttention(message) }
            }
        case .stop:
            session.state = .done
            session.activity = nil
        case .subagentStop:
            break
        case .sessionEnd:
            return
        }

        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        onChange?()
    }

    public func dismiss(_ id: String) {
        sessions.removeAll { $0.id == id }
        onChange?()
    }

    public var pillStatus: PillStatus? {
        let attention = attentionSessions
        if let first = attention.first {
            let text = attention.count == 1 ? "\(first.projectName) needs you" : "\(attention.count) agents need you"
            return PillStatus(text: text, systemImage: "terminal.fill", priority: .attention)
        }
        let finished = sessions.filter { $0.state == .done }
        if let first = finished.first {
            let text = finished.count == 1 ? "\(first.projectName) finished" : "\(finished.count) agents finished"
            return PillStatus(text: text, systemImage: "checkmark.circle.fill", priority: .info)
        }
        let working = workingSessions
        guard !working.isEmpty else { return nil }
        let text = working.count == 1 ? (working[0].activity ?? working[0].projectName) : "\(working.count) agents working"
        return PillStatus(text: text, systemImage: "terminal", priority: .info)
    }

    static func summarize(_ prompt: String) -> String {
        let firstLine = prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? prompt
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 80 ? String(trimmed.prefix(79)) + "…" : trimmed
    }
}
