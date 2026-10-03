import Foundation
import IsletCore
import Testing
@testable import AgentsPlugin

struct ReviewAlertTests {
    @Test func announcesWhenReviewStateChangesToApprovedOrChangesRequested() {
        var alert = ReviewAlert()
        var session = Self.session(number: 42, reviewState: "pending")
        #expect(alert.announcement(for: session) == nil)

        session.details.pullRequest?.reviewState = "approved"
        let approved = alert.announcement(for: session)
        #expect(approved?.text == "proj · PR #42 approved")
        #expect(approved?.priority == .info)

        #expect(alert.announcement(for: session) == nil)

        session.details.pullRequest?.reviewState = "changes_requested"
        #expect(alert.announcement(for: session)?.text == "proj · PR #42 changes requested")

        session.details.pullRequest = nil
        #expect(alert.announcement(for: session) == nil)
        session.details.pullRequest = SessionDetails.PullRequest(number: 42, url: nil, reviewState: "approved", isMergeRequest: false)
        #expect(alert.announcement(for: session) == nil)
    }

    private static func session(number: Int, reviewState: String?) -> AgentSession {
        var session = AgentSession(id: "s", agent: .claudeCode, host: nil, cwd: "/tmp/proj", task: nil, activity: nil, state: .working, startedAt: .now, turnStartedAt: .now, updatedAt: .now)
        session.details.pullRequest = SessionDetails.PullRequest(number: number, url: "https://example.com/\(number)", reviewState: reviewState, isMergeRequest: false)
        return session
    }
}
