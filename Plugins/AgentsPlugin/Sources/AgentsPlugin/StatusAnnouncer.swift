import IsletCore

struct StatusAnnouncer {
    private enum Category {
        case attention, finished, other
    }

    private var categories: [String: Category] = [:]

    mutating func announcement(for sessions: [AgentSession]) -> PillAnnouncement? {
        let changed = sessions.filter { categories[$0.id] != Self.category(of: $0.state) }
        categories = Dictionary(sessions.map { ($0.id, Self.category(of: $0.state)) }, uniquingKeysWith: { first, _ in first })
        let announcements = changed.compactMap(Self.announcement(for:))
        return announcements.first { $0.priority == .attention } ?? announcements.first
    }

    static func announcement(for session: AgentSession) -> PillAnnouncement? {
        switch session.state {
        case .needsAttention(let reason):
            PillAnnouncement(text: "\(session.displayName) · \(reason)", systemImage: "exclamationmark.circle.fill", tint: SessionColors.attentionTint, priority: .attention)
        case .failed(let reason):
            PillAnnouncement(text: "\(session.displayName) · \(reason)", systemImage: "xmark.octagon.fill", tint: SessionColors.failedTint, priority: .attention)
        case .done:
            PillAnnouncement(text: "\(session.displayName) finished", systemImage: "checkmark.circle.fill", tint: SessionColors.finishedTint)
        case .starting, .working, .interrupted:
            nil
        }
    }

    private static func category(of state: AgentSession.State) -> Category {
        switch state {
        case .needsAttention, .failed: .attention
        case .done: .finished
        case .starting, .working, .interrupted: .other
        }
    }
}
