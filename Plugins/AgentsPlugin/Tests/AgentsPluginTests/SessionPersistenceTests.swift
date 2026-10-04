import Foundation
import Testing
@testable import AgentsPlugin

@MainActor
struct SessionPersistenceTests {
    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "SessionPersistenceTests." + UUID().uuidString, directoryHint: .isDirectory)
    }

    private func populatedStore() -> AgentSessionStore {
        let store = AgentSessionStore(localHost: { "mac" })
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "local", cwd: "/tmp/proj", prompt: "Fix the bug", terminal: TerminalApp(identifier: "iTerm.app"), pid: 100, title: "Bug fix"))
        store.apply(HookEvent(kind: .preToolUse, sessionID: "local", toolName: "Read", toolInput: .object(["file_path": .string("/a/b.swift")]), pid: 100))
        store.apply(HookEvent(kind: .permissionRequest, sessionID: "local", toolName: "ExitPlanMode", toolInput: .object(["plan": .string("# Plan")]), pid: 100))
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "remote", cwd: "/srv", prompt: "Remote task", host: "other", pid: 5))
        return store
    }

    @Test func roundTripsSessionsWithActivitiesPlanAndTitle() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = populatedStore()
        let persistence = SessionPersistence(directory: directory)
        persistence.save(store.snapshot())

        let restored = AgentSessionStore(localHost: { "mac" })
        restored.restore(try #require(persistence.load()), isRunning: { _ in true })
        let session = try #require(restored.sessions.first { $0.id == "local" })
        #expect(session.title == "Bug fix")
        #expect(session.task == "Fix the bug")
        #expect(session.plan == "# Plan")
        #expect(session.activities.map(\.title) == ["Read b.swift"])
        #expect(session.terminal == TerminalApp(identifier: "iTerm.app"))
        #expect(restored.sessions.count == 2)
    }

    @Test func restoreDropsExitedLocalSessionsAndKeepsRemoteOnes() {
        let store = populatedStore()
        let restored = AgentSessionStore(localHost: { "mac" })
        restored.restore(store.snapshot(), isRunning: { _ in false })
        #expect(restored.sessions.map(\.id) == ["remote"])
    }

    @Test func restoreDropsSessionsWithoutPid() {
        let store = AgentSessionStore(localHost: { "mac" })
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "nopid", prompt: "hi"))
        let restored = AgentSessionStore(localHost: { "mac" })
        restored.restore(store.snapshot(), isRunning: { _ in true })
        #expect(restored.sessions.isEmpty)
    }

    @Test func restoreClearsPendingRequestsAndKeepsOtherStates() async throws {
        let store = AgentSessionStore(localHost: { "mac" })
        let handled = Task { await store.handle(HookEvent(kind: .permissionRequest, sessionID: "s", toolName: "Bash", toolInput: .object(["command": .string("ls")]), pid: 1)) }
        for _ in 0..<200 where store.sessions.first?.pendingRequests.isEmpty != false {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.sessions[0].pendingRequests.count == 1)
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "w", prompt: "go", pid: 2))
        let snapshot = store.snapshot()
        handled.cancel()

        let restored = AgentSessionStore(localHost: { "mac" })
        restored.restore(snapshot, isRunning: { _ in true })
        let attention = try #require(restored.sessions.first { $0.id == "s" })
        #expect(attention.pendingRequests.isEmpty)
        #expect(attention.state == .needsAttention("Waiting for your answer in the terminal"))
        #expect(restored.sessions.first { $0.id == "w" }?.state == .working)
    }

    @Test func corruptFileIsRenamedAndLoadsNothing() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let persistence = SessionPersistence(directory: directory)
        try Data("not json".utf8).write(to: persistence.fileURL)
        #expect(persistence.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: persistence.fileURL.path))
        #expect(FileManager.default.fileExists(atPath: persistence.fileURL.appendingPathExtension("corrupt").path))
    }

    @Test func changesAreWrittenWithinTheDebounceWindow() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = AgentsController(token: "t", home: directory, port: 0, storageDirectory: directory, saveDelay: .milliseconds(50))
        controller.store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "s", prompt: "go", pid: 1))
        controller.sessionsDidChange()
        let file = SessionPersistence(directory: directory).fileURL
        for _ in 0..<300 where !FileManager.default.fileExists(atPath: file.path) {
            try await Task.sleep(for: .milliseconds(10))
        }
        let snapshot = try #require(SessionPersistence(directory: directory).load())
        #expect(snapshot.sessions.map(\.id) == ["s"])
    }

    @Test func dismissedSessionsStayDismissedWhileTheirProcessRuns() {
        let store = populatedStore()
        store.dismiss("local")

        let restored = AgentSessionStore(localHost: { "mac" })
        restored.restore(store.snapshot(), isRunning: { _ in true })
        restored.apply(HookEvent(kind: .preToolUse, sessionID: "local", toolName: "Read", pid: 100))
        #expect(!restored.sessions.contains { $0.id == "local" })

        let exited = AgentSessionStore(localHost: { "mac" })
        exited.restore(store.snapshot(), isRunning: { $0 != 100 })
        #expect(exited.snapshot().dismissed?.isEmpty == true)
    }

    @Test func statusLineModelSurvivesARestore() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AgentSessionStore(localHost: { "mac" })
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "s", prompt: "go", agent: .antigravity, pid: 1))
        store.applyStatusLine(StatusLineUpdate(sessionID: "s", details: SessionDetails(model: "Gemini 3 Pro")))
        let persistence = SessionPersistence(directory: directory)
        persistence.save(store.snapshot())

        let restored = AgentSessionStore(localHost: { "mac" })
        restored.restore(try #require(persistence.load()), isRunning: { _ in true })
        var event = HookEvent(kind: .postToolUse, sessionID: "s", toolName: "Read", agent: .antigravity, pid: 1)
        event.model = "Gemini Flash"
        restored.apply(event)
        #expect(restored.sessions.first?.details.model == "Gemini 3 Pro")
    }

    @Test func restoredSessionsAndCostsAreNotAnnouncedOrCountedAgain() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pid = getpid()
        let store = AgentSessionStore(localHost: { "mac" })
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "s", prompt: "go", pid: pid))
        store.apply(HookEvent(kind: .stop, sessionID: "s", pid: pid))
        var snapshot = store.snapshot()
        var costs = CostTracker()
        costs.record(sessionID: "s", cost: 12, at: .now)
        snapshot.costs = costs
        SessionPersistence(directory: directory).save(snapshot)

        let controller = AgentsController(token: "t", home: directory, port: 0, storageDirectory: directory)
        await controller.start()
        defer { Task { await controller.stop() } }
        #expect(controller.store.sessions.map(\.id) == ["s"])
        #expect(controller.sessionsDidChange().isEmpty)
        #expect(controller.dailyCost == 12)
        controller.usage.record(sessionID: "s", cost: 12.5)
        #expect(controller.dailyCost == 12.5)
    }
}
