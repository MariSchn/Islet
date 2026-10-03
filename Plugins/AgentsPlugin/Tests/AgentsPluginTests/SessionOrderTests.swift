import Foundation
import Testing
@testable import AgentsPlugin

@MainActor
struct SessionOrderTests {
    private func session(_ id: String, _ state: AgentSession.State, unreachable: Bool = false) -> AgentSession {
        var session = AgentSession(id: id, agent: .claudeCode, host: nil, cwd: nil, task: nil, activity: nil, state: state, startedAt: .now, turnStartedAt: .now, updatedAt: .now)
        session.isUnreachable = unreachable
        return session
    }

    @Test func groupsByUrgencyAndKeepsTheOrderWithinAGroup() {
        let sessions = [
            session("done1", .done),
            session("work1", .working),
            session("int", .interrupted),
            session("fail", .failed("x")),
            session("start", .starting),
            session("work2", .working),
            session("gone", .working, unreachable: true),
            session("ask", .needsAttention("y")),
            session("done2", .done),
        ]
        #expect(SessionOrder.sorted(sessions).map(\.id) == ["fail", "ask", "work1", "work2", "start", "done1", "done2", "int", "gone"])
    }

    @Test func aSessionNeedingAttentionMovesUpAndReturnsAfterTheDecision() async throws {
        let store = AgentSessionStore()
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "a", prompt: "go"))
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "b", prompt: "go"))
        #expect(store.orderedSessions.map(\.id) == ["b", "a"])

        let handled = Task { await store.handle(HookEvent(kind: .permissionRequest, sessionID: "a", toolName: "Bash", toolInput: .object(["command": .string("ls")]))) }
        for _ in 0..<200 where store.sessions.first(where: { $0.id == "a" })?.pendingRequests.isEmpty != false {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.orderedSessions.map(\.id) == ["a", "b"])

        let request = try #require(store.sessions.first { $0.id == "a" }?.pendingRequests.first)
        store.decide(request.id, .allow)
        _ = await handled.value
        #expect(store.orderedSessions.map(\.id) == ["b", "a"])
    }

    @Test func frozenOrderKeepsPositionsAndAppendsNewSessions() {
        let sessions = [session("a", .needsAttention("x")), session("b", .working), session("c", .working)]
        let frozen = ["b", "a", "c"]
        let later = sessions + [session("d", .needsAttention("y"))]
        #expect(SessionOrder.applying(frozen: frozen, to: SessionOrder.sorted(later)).map(\.id) == ["b", "a", "c", "d"])
        #expect(SessionOrder.applying(frozen: ["b", "gone", "a"], to: SessionOrder.sorted(sessions)).map(\.id) == ["b", "a", "c"])
        #expect(SessionOrder.applying(frozen: nil, to: SessionOrder.sorted(sessions)).map(\.id) == ["a", "b", "c"])
    }
}
