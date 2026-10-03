import Foundation
import IsletCore
import Testing
@testable import AgentsPlugin

struct ContextAlertTests {
    @Test func announcesOnceUntilContextDropsBelowEighty() {
        var alert = ContextAlert()
        var session = Self.session(85)
        let first = alert.announcement(for: session)
        #expect(first?.text == "proj · context 85% full")
        #expect(first?.systemImage == "gauge.with.dots.needle.67percent")
        #expect(first?.priority == .info)

        session.details.contextPercentage = 90
        #expect(alert.announcement(for: session) == nil)
        session.details.contextPercentage = 80
        #expect(alert.announcement(for: session) == nil)
        session.details.contextPercentage = 79
        #expect(alert.announcement(for: session) == nil)
        session.details.contextPercentage = 86
        #expect(alert.announcement(for: session)?.text == "proj · context 86% full")
    }

    private static func session(_ percentage: Double) -> AgentSession {
        var session = AgentSession(id: "s", agent: .claudeCode, host: nil, cwd: "/tmp/proj", task: nil, activity: nil, state: .working, startedAt: .now, turnStartedAt: .now, updatedAt: .now)
        session.details.contextPercentage = percentage
        return session
    }
}
