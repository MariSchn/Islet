import Foundation
import Testing
@testable import AgentsPlugin

@MainActor
struct MuteTests {
    private func makeController() -> AgentsController {
        let directory = FileManager.default.temporaryDirectory.appending(path: "MuteTests." + UUID().uuidString)
        return AgentsController(token: "t", claudeDirectory: directory, codexDirectory: directory, antigravityDirectory: directory, port: 0)
    }

    private func session(_ id: String, state: AgentSession.State = .done) -> AgentSession {
        AgentSession(id: id, agent: .claudeCode, host: nil, cwd: "/tmp/\(id)", task: nil, activity: nil, state: state, startedAt: .now, turnStartedAt: .now, updatedAt: .now)
    }

    @Test func alertsForMutedSessionsAreNotForwarded() {
        let controller = makeController()
        controller.toggleMute("a")
        #expect(!controller.shouldAlert(.finished(session("a"))))
        #expect(!controller.shouldAlert(.needsAttention(session("a", state: .needsAttention("x")))))
        #expect(controller.shouldAlert(.finished(session("b"))))
        controller.toggleMute("a")
        #expect(controller.shouldAlert(.finished(session("a"))))
    }

    @Test func announcementsSkipMutedSessionsOnly() {
        var announcer = StatusAnnouncer()
        let announcement = announcer.announcement(for: [session("a"), session("b")], muted: ["a"])
        #expect(announcement?.text == "b finished")
        #expect(announcer.announcement(for: [session("a"), session("b")], muted: []) == nil)

        var contextAlert = ContextAlert()
        var hot = session("a")
        hot.details.contextPercentage = 90
        #expect(contextAlert.announcements(for: [hot], muted: ["a"]).isEmpty)
        var other = ContextAlert()
        #expect(other.announcements(for: [hot]).count == 1)
    }

    @Test func mutingDoesNotChangeThePillStatus() {
        let controller = makeController()
        controller.store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "a", cwd: "/tmp/a", prompt: "go"))
        controller.store.apply(HookEvent(kind: .notification, sessionID: "a", message: "Needs input", notificationType: "permission_prompt"))
        let before = controller.store.pillStatus(for: controller.display)
        controller.toggleMute("a")
        #expect(controller.store.pillStatus(for: controller.display) == before)
    }

    @Test func endedSessionsLoseTheirMute() {
        let controller = makeController()
        controller.store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "a", cwd: "/tmp/a", prompt: "go"))
        controller.store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "b", cwd: "/tmp/b", prompt: "go"))
        controller.toggleMute("a")
        controller.toggleMute("b")
        controller.pruneMutedSessions()
        #expect(controller.mutedSessionIDs == ["a", "b"])
        controller.store.apply(HookEvent(kind: .sessionEnd, sessionID: "a"))
        controller.pruneMutedSessions()
        #expect(controller.mutedSessionIDs == ["b"])
        controller.store.dismiss("b")
        controller.pruneMutedSessions()
        #expect(controller.mutedSessionIDs.isEmpty)
    }
}
