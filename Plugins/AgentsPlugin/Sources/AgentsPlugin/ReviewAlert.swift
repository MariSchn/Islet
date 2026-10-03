import IsletCore

struct ReviewAlert {
    private struct Seen: Equatable {
        var number: Int
        var reviewState: String?
    }

    private var seen: [String: Seen] = [:]

    mutating func announcements(for sessions: [AgentSession], muted: Set<String> = []) -> [PillAnnouncement] {
        var announcements: [PillAnnouncement] = []
        for session in sessions {
            if let announcement = announcement(for: session), !muted.contains(session.id) {
                announcements.append(announcement)
            }
        }
        return announcements
    }

    mutating func announcement(for session: AgentSession) -> PillAnnouncement? {
        guard let pullRequest = session.details.pullRequest else {
            seen.removeValue(forKey: session.id)
            return nil
        }
        let current = Seen(number: pullRequest.number, reviewState: pullRequest.reviewState)
        let previous = seen[session.id]
        seen[session.id] = current
        guard let previous, previous.number == current.number, previous.reviewState != current.reviewState else { return nil }
        let words: String
        switch current.reviewState {
        case "approved": words = "approved"
        case "changes_requested": words = "changes requested"
        default: return nil
        }
        return PillAnnouncement(
            text: "\(session.displayName) · \(pullRequest.announcementMark) \(words)",
            systemImage: "arrow.triangle.merge",
            priority: .info
        )
    }
}
