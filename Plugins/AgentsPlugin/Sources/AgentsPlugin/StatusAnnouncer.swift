import IsletCore

struct StatusAnnouncer {
    private var states: [String: AgentSession.State] = [:]

    mutating func announcement(for sessions: [AgentSession]) -> PillAnnouncement? {
        let changed = sessions.filter { states[$0.id] != $0.state }
        states = Dictionary(sessions.map { ($0.id, $0.state) }, uniquingKeysWith: { first, _ in first })
        return changed
            .compactMap { session in Self.announcement(for: session).map { (rank: Self.rank(of: session.state), announcement: $0) } }
            .max { $0.rank < $1.rank }?
            .announcement
    }

    static func announcement(for session: AgentSession) -> PillAnnouncement? {
        switch session.state {
        case .needsAttention(let reason):
            PillAnnouncement(text: "\(session.displayName) · \(reason)", systemImage: "exclamationmark.circle.fill", tint: SessionColors.attentionTint)
        case .done:
            PillAnnouncement(text: "\(session.displayName) finished", systemImage: "checkmark.circle.fill", tint: SessionColors.finishedTint)
        case .interrupted:
            PillAnnouncement(text: "\(session.displayName) interrupted", systemImage: "stop.circle.fill", tint: SessionColors.idleTint)
        case .starting, .working:
            nil
        }
    }

    private static func rank(of state: AgentSession.State) -> Int {
        switch state {
        case .needsAttention: 3
        case .done: 2
        case .interrupted: 1
        case .starting, .working: 0
        }
    }
}
