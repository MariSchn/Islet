enum SessionOrder {
    static func sorted(_ sessions: [AgentSession]) -> [AgentSession] {
        sessions.enumerated()
            .sorted { lhs, rhs in
                let (left, right) = (group(lhs.element), group(rhs.element))
                return left != right ? left < right : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    static func applying(frozen: [String]?, to sorted: [AgentSession]) -> [AgentSession] {
        guard let frozen else { return sorted }
        let positions = Dictionary(frozen.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let known = sorted.filter { positions[$0.id] != nil }.sorted { positions[$0.id]! < positions[$1.id]! }
        return known + sorted.filter { positions[$0.id] == nil }
    }

    private static func group(_ session: AgentSession) -> Int {
        switch session.state {
        case .needsAttention, .failed: 0
        case .working where !session.isUnreachable: 1
        case .starting: 2
        case .done: 3
        case .working, .interrupted: 4
        }
    }
}
