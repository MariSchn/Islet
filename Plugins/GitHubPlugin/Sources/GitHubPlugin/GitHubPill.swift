import IsletCore
import SwiftUI

enum GitHubPill {
    static let failingTint = Color.Resolved(red: 1, green: 0.27, blue: 0.23)
    static let pendingTint = Color.Resolved(red: 1, green: 0.8, blue: 0.04)
    static let passingTint = Color.Resolved(red: 0.2, green: 0.78, blue: 0.35)

    static func status(for snapshot: GitHubSnapshot) -> PillStatus? {
        let count = snapshot.mine.count + snapshot.reviewRequested.count
        guard count > 0 else { return nil }
        let ring = ring(for: snapshot.mine)
        let needsAttention = snapshot.mine.contains { $0.checks == .failing } || !snapshot.reviewRequested.isEmpty
        return PillStatus(
            text: count == 1 ? "1 PR" : "\(count) PRs",
            systemImage: "arrow.triangle.pull",
            priority: needsAttention ? .attention : .ambient,
            ring: ring.segments.isEmpty ? nil : ring
        )
    }

    static func ring(for pullRequests: [PullRequest]) -> PillStatus.Ring {
        func count(_ status: CheckStatus) -> Double {
            Double(pullRequests.count { $0.checks == status })
        }
        return PillStatus.Ring(segments: [
            .init(value: count(.failing), tint: failingTint),
            .init(value: count(.pending), tint: pendingTint),
            .init(value: count(.passing), tint: passingTint),
        ].filter { $0.value > 0 })
    }
}
