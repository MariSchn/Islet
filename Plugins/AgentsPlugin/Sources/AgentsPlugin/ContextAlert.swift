import IsletCore

struct ContextAlert {
    private var fired: Set<String> = []

    mutating func announcements(for sessions: [AgentSession]) -> [PillAnnouncement] {
        var announcements: [PillAnnouncement] = []
        for session in sessions {
            if let announcement = announcement(for: session) {
                announcements.append(announcement)
            }
        }
        return announcements
    }

    mutating func announcement(for session: AgentSession) -> PillAnnouncement? {
        guard let percentage = session.details.contextPercentage else { return nil }
        if percentage < 80 {
            fired.remove(session.id)
            return nil
        }
        guard percentage >= 85, fired.insert(session.id).inserted else { return nil }
        let text = "\(session.displayName) · context \(SessionDetails.percentText(percentage))% full"
        return PillAnnouncement(text: text, systemImage: "gauge.with.dots.needle.67percent", priority: .info)
    }
}
