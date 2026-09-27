import Foundation
import Testing
@testable import AgentsPlugin

struct HookEventTests {
    @Test func decodesClaudeCodePayloadAndDescribesTools() throws {
        let json = """
        {"session_id":"abc","cwd":"/Users/me/projects/islet","hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"/Users/me/projects/islet/App/Main.swift","old_string":"a"}}
        """
        let event = try HookEvent.decode(Data(json.utf8), host: "mac")
        #expect(event.kind == .preToolUse)
        #expect(event.sessionID == "abc")
        #expect(event.host == "mac")
        #expect(event.activityDescription == "Edit Main.swift")

        let bash = HookEvent(kind: .preToolUse, sessionID: "x", toolName: "Bash", toolInput: .object(["command": .string("swift test"), "description": .string("Run tests")]))
        #expect(bash.activityDescription == "Run tests")
        let rawBash = HookEvent(kind: .preToolUse, sessionID: "x", toolName: "Bash", toolInput: .object(["command": .string("ls")]))
        #expect(rawBash.activityDescription == "$ ls")
        #expect(HookEvent(kind: .preToolUse, sessionID: "x", toolName: "Mystery").activityDescription == "Mystery")
        let codexShell = HookEvent(kind: .preToolUse, sessionID: "x", toolName: "shell", toolInput: .object(["command": .array([.string("ls"), .string("-la")])]))
        #expect(codexShell.activityDescription == "$ ls -la")
        #expect(PendingRequest(toolName: "shell", toolInput: codexShell.toolInput)?.kind == .permission(tool: "shell", detail: "ls -la"))
        #expect(HookEvent(kind: .preToolUse, sessionID: "x", toolName: "apply_patch").activityDescription == "Apply patch")
        #expect(try HookEvent.decode(Data(#"{"session_id":"a","hook_event_name":"Stop"}"#.utf8), agent: "codex").agent == .codex)
        #expect(try HookEvent.decode(Data(#"{"session_id":"a","hook_event_name":"Stop"}"#.utf8), agent: "unknown").agent == .claudeCode)
        let auto = try HookEvent.decode(Data(#"{"session_id":"a","hook_event_name":"PermissionRequest","permission_mode":"auto","agent_type":"Explore"}"#.utf8))
        #expect(auto.isInAutoMode)
        #expect(auto.agentType == "Explore")
        #expect(!event.isInAutoMode)
    }

    @Test func resolvesTheHostingTerminalFromBundleIdentifierOrProgramName() throws {
        let payload = Data(#"{"session_id":"a","hook_event_name":"Stop"}"#.utf8)
        #expect(try HookEvent.decode(payload, terminal: "com.googlecode.iterm2").terminal == TerminalApp(identifier: "com.googlecode.iterm2"))
        #expect(try HookEvent.decode(payload, terminal: "Apple_Terminal").terminal?.bundleIdentifier == "com.apple.Terminal")
        #expect(try HookEvent.decode(payload, terminal: " ").terminal == nil)
        #expect(try HookEvent.decode(payload).terminal == nil)
        #expect(try HookEvent.decode(payload, tty: "/dev/ttys004").tty == "/dev/ttys004")
        #expect(try HookEvent.decode(payload, tty: "").tty == nil)
        #expect(try HookEvent.decode(payload, tty: "/dev/x\" then do shell script \"id\"").tty == nil)
        #expect(try HookEvent.decode(payload, terminal: "com.example.app\"").terminal == nil)
        #expect(try HookEvent.decode(payload, title: "islet-main").title == "islet-main")
        #expect(try HookEvent.decode(payload, title: "").title == nil)
        #expect(TerminalApp(identifier: "Apple_Terminal")?.targeting == .terminalTab)
        #expect(TerminalApp(identifier: "com.todesktop.230313mzl4w4u92")?.targeting == .editorFolder)
        #expect(TerminalApp(identifier: "cursor")?.bundleIdentifier == "com.todesktop.230313mzl4w4u92")
        #expect(TerminalApp(identifier: "ghostty")?.targeting == .application)
    }

    @Test func describesLineCountsForFileTools() {
        #expect(ActivityEntry.detail(for: "Edit", input: .object(["old_string": .string("a\nb"), "new_string": .string("a\nb\nc")])) == "+3 −2")
        #expect(ActivityEntry.detail(for: "Write", input: .object(["content": .string("x\ny\n")])) == "3 lines")
        #expect(ActivityEntry.detail(for: "Read", input: .object(["offset": .number(10), "limit": .number(20)])) == "lines 10–29")
        #expect(ActivityEntry.detail(for: "Read", input: .object(["file_path": .string("/a")])) == nil)
        #expect(ActivityEntry.detail(for: "Grep", input: .object(["path": .string("/Users/me/repo/Sources")])) == "Sources")
        #expect(ActivityEntry.detail(for: "Bash", input: .object(["command": .string("ls")])) == nil)
    }

    @Test func acceptsOnlyPlausibleProcessIDs() throws {
        let payload = Data(#"{"session_id":"a","hook_event_name":"Stop"}"#.utf8)
        #expect(try HookEvent.decode(payload, pid: "4242").pid == 4242)
        #expect(try HookEvent.decode(payload, pid: "1").pid == nil)
        #expect(try HookEvent.decode(payload, pid: "").pid == nil)
        #expect(try HookEvent.decode(payload, pid: "12; rm").pid == nil)
    }

    @Test func rejectsUnknownEvents() {
        #expect(throws: (any Error).self) {
            try HookEvent.decode(Data(#"{"session_id":"a","hook_event_name":"Nope"}"#.utf8))
        }
    }
}

@MainActor
struct AgentSessionStoreTests {
    @Test func recordsRecentToolCallsAndPlans() {
        let store = AgentSessionStore()
        let read = JSONValue.object(["file_path": .string("/a/b.swift")])
        store.apply(HookEvent(kind: .preToolUse, sessionID: "s1", toolName: "Read", toolInput: read))
        #expect(store.sessions[0].activities.map(\.title) == ["Read b.swift"])
        #expect(store.sessions[0].activities[0].isComplete == false)

        store.apply(HookEvent(kind: .postToolUse, sessionID: "s1", toolName: "Read", toolInput: read))
        #expect(store.sessions[0].activities.count == 1)
        #expect(store.sessions[0].activities[0].isComplete == true)

        store.apply(HookEvent(kind: .postToolUse, sessionID: "s1", toolName: "Bash", toolInput: .object(["command": .string("ls")])))
        #expect(store.sessions[0].activities.map(\.title) == ["Read b.swift", "$ ls"])

        for index in 0..<ActivityEntry.limit {
            store.apply(HookEvent(kind: .postToolUse, sessionID: "s1", toolName: "Grep", toolInput: .object(["pattern": .string("\(index)")])))
        }
        #expect(store.sessions[0].activities.count == ActivityEntry.limit)
        #expect(store.sessions[0].activities.first?.title == "Search 0")

        #expect(store.sessions[0].plan == nil)
        store.apply(HookEvent(kind: .permissionRequest, sessionID: "s1", toolName: "ExitPlanMode", toolInput: .object(["plan": .string("# Do it\n- step")])))
        #expect(store.sessions[0].plan == "# Do it\n- step")
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "s1", prompt: "go"))
        #expect(store.sessions[0].plan == "# Do it\n- step")
    }

    @Test func walksThroughSessionLifecycle() {
        let store = AgentSessionStore()
        store.apply(HookEvent(kind: .sessionStart, sessionID: "s1", cwd: "/tmp/proj"))
        #expect(store.sessions.count == 1)
        #expect(store.sessions[0].state == .starting)
        #expect(store.sessions[0].projectName == "proj")
        #expect(store.pillStatus == nil)

        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "s1", prompt: "fix the auth bug\nmore details"))
        #expect(store.sessions[0].task == "fix the auth bug")
        #expect(store.sessions[0].state == .working)
        #expect(store.pillStatus?.text == "proj")

        store.apply(HookEvent(kind: .preToolUse, sessionID: "s1", toolName: "Read", toolInput: .object(["file_path": .string("/a/b.swift")])))
        #expect(store.sessions[0].activity == "Read b.swift")
        #expect(store.pillStatus?.text == "Read b.swift")

        store.apply(HookEvent(kind: .notification, sessionID: "s1", message: "Claude needs your permission to use Bash", notificationType: "permission_prompt"))
        #expect(store.sessions[0].state == .needsAttention("Claude needs your permission to use Bash"))
        #expect(store.pillStatus?.priority == .attention)
        #expect(store.pillStatus?.text == "proj needs you")

        store.apply(HookEvent(kind: .postToolUse, sessionID: "s1", toolName: "Bash"))
        #expect(store.sessions[0].state == .working)

        store.apply(HookEvent(kind: .stop, sessionID: "s1"))
        #expect(store.sessions[0].state == .done)
        #expect(store.pillStatus?.text == "proj finished")

        store.apply(HookEvent(kind: .notification, sessionID: "s1", notificationType: "idle_prompt"))
        #expect(store.sessions[0].state == .done)

        store.apply(HookEvent(kind: .sessionEnd, sessionID: "s1"))
        #expect(store.sessions.isEmpty)
    }

    @Test func ignoresIrrelevantNotificationsAndCompaction() {
        let store = AgentSessionStore()
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "s", cwd: "/p", prompt: "go"))
        store.apply(HookEvent(kind: .notification, sessionID: "s", message: "Authentication successful", notificationType: "auth_success"))
        #expect(store.sessions[0].state == .working)
        store.apply(HookEvent(kind: .sessionStart, sessionID: "s", source: "compact"))
        #expect(store.sessions[0].state == .working)
        store.apply(HookEvent(kind: .notification, sessionID: "s", notificationType: "idle_prompt"))
        #expect(store.sessions[0].state == .needsAttention("Waiting for your input"))
        store.apply(HookEvent(kind: .notification, sessionID: "s", message: "Pick one", notificationType: "elicitation_dialog"))
        #expect(store.sessions[0].state == .needsAttention("Pick one"))
    }

    @Test func dismissedSessionsStayHiddenUntilTheNextPrompt() {
        let store = AgentSessionStore()
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "s", cwd: "/p", prompt: "go"))
        store.dismiss("s")
        store.apply(HookEvent(kind: .postToolUse, sessionID: "s", toolName: "Read"))
        store.apply(HookEvent(kind: .stop, sessionID: "s"))
        #expect(store.sessions.isEmpty)
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "s", prompt: "again"))
        #expect(store.sessions.count == 1)
        #expect(store.sessions[0].task == "again")
    }

    @Test func finishedSessionsLeaveThePillAfterAWhileAndYieldToWorkingOnes() {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let store = AgentSessionStore { clock }
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "a", cwd: "/one", prompt: "x"))
        store.apply(HookEvent(kind: .stop, sessionID: "a"))
        #expect(store.pillStatus?.text == "one finished")

        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "b", cwd: "/two", prompt: "y"))
        #expect(store.pillStatus?.text == "two")
        store.apply(HookEvent(kind: .sessionEnd, sessionID: "b"))
        #expect(store.pillStatus?.text == "one finished")

        clock = clock.addingTimeInterval(AgentSessionStore.finishedPillDuration + 1)
        #expect(store.pillStatus == nil)
        #expect(store.sessions.count == 1)
    }

    @Test func remoteSessionsShowTheirHostAndGoUnreachableWithoutUpdates() {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let store = AgentSessionStore(now: { clock }, localHost: { "MacBook" })
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "local", cwd: "/one", prompt: "x", host: "macbook"))
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "remote", cwd: "/two", prompt: "y", host: "devbox"))
        #expect(store.sessions.map(\.isRemote) == [true, false])
        #expect(store.pillStatus?.text == "2 agents working")

        clock = clock.addingTimeInterval(AgentSessionStore.unreachableTimeout + 1)
        store.markUnreachableSessions()
        #expect(store.sessions.map(\.isUnreachable) == [true, false])
        #expect(store.pillStatus?.text == "one")

        store.apply(HookEvent(kind: .preToolUse, sessionID: "remote", toolName: "Read"))
        #expect(store.sessions[0].isUnreachable == false)
        store.apply(HookEvent(kind: .stop, sessionID: "remote"))
        clock = clock.addingTimeInterval(AgentSessionStore.unreachableTimeout + 1)
        store.markUnreachableSessions()
        #expect(store.sessions[0].isUnreachable == false)
    }

    @Test func sessionsWithoutAPromptShowNoRunningTurn() {
        let store = AgentSessionStore()
        store.apply(HookEvent(kind: .sessionStart, sessionID: "s", cwd: "/p"))
        #expect(store.sessions[0].state == .starting)
        #expect(store.sessions[0].task == nil)
        #expect(store.workingSessions.isEmpty)
        #expect(store.pillStatus == nil)
    }

    @Test func aClaudeProcessOnlyKeepsItsLatestSession() {
        let store = AgentSessionStore(localHost: { "mac" })
        store.apply(HookEvent(kind: .sessionStart, sessionID: "startup", cwd: "/p", host: "mac", pid: 42))
        store.apply(HookEvent(kind: .sessionStart, sessionID: "other-host", cwd: "/p", host: "devbox", pid: 42))
        store.apply(HookEvent(kind: .sessionStart, sessionID: "resumed", cwd: "/p", host: "mac", pid: 42))
        #expect(store.sessions.map(\.id) == ["resumed", "other-host"])

        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "resumed", prompt: "go", host: "mac", pid: 42))
        store.apply(HookEvent(kind: .preToolUse, sessionID: "resumed", toolName: "WebSearch", host: "mac", pid: 42))
        store.apply(HookEvent(kind: .sessionStart, sessionID: "after-backgrounding", cwd: "/p", host: "mac", pid: 42))
        #expect(store.sessions.map(\.id) == ["after-backgrounding", "other-host"])

        store.apply(HookEvent(kind: .sessionStart, sessionID: "fork-spare", cwd: "/p", host: "mac", pid: 50))
        store.apply(HookEvent(kind: .sessionStart, sessionID: "fork", cwd: "/p", source: "fork", host: "mac", pid: 50))
        store.apply(HookEvent(kind: .sessionStart, sessionID: "late-spare", cwd: "/p", host: "mac", pid: 50))
        store.apply(HookEvent(kind: .preToolUse, sessionID: "fork", toolName: "Read", host: "mac", pid: 50))
        #expect(store.sessions.map(\.id) == ["fork", "after-backgrounding", "other-host"])

        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "busy", prompt: "x", host: "mac", pid: 60))
        store.apply(HookEvent(kind: .preToolUse, sessionID: "sibling", toolName: "Read", host: "mac", pid: 60))
        #expect(store.sessions.contains { $0.id == "busy" })

        store.apply(HookEvent(kind: .sessionStart, sessionID: "codex-a", cwd: "/p", agent: .codex, host: "mac", pid: 70))
        store.apply(HookEvent(kind: .sessionStart, sessionID: "codex-b", cwd: "/p", agent: .codex, host: "mac", pid: 70))
        #expect(store.sessions.contains { $0.id == "codex-a" } && store.sessions.contains { $0.id == "codex-b" })
    }

    @Test func forkedAndResumedSessionsShowTheirLastPrompt() async throws {
        let store = AgentSessionStore(localHost: { "mac" }, lastPrompt: { $0 == "/t/bg.jsonl" ? "Research something on the web\nand ask me" : "unexpected read" })
        store.apply(HookEvent(kind: .sessionStart, sessionID: "bg", cwd: "/p", transcriptPath: "/t/bg.jsonl", source: "fork", host: "mac", pid: 7))
        try await waitUntil { store.sessions.first { $0.id == "bg" }?.task != nil }
        #expect(store.sessions.first { $0.id == "bg" }?.task == "Research something on the web")

        store.apply(HookEvent(kind: .sessionStart, sessionID: "fresh", cwd: "/p", transcriptPath: "/t/fresh.jsonl", source: "startup", host: "mac", pid: 8))
        store.apply(HookEvent(kind: .sessionStart, sessionID: "remote", cwd: "/p", transcriptPath: "/t/remote.jsonl", source: "resume", host: "devbox", pid: 9))
        store.apply(HookEvent(kind: .sessionStart, sessionID: "prompted", cwd: "/p", transcriptPath: "/t/prompted.jsonl", source: "resume", host: "mac", pid: 10))
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "prompted", prompt: "newer prompt", host: "mac", pid: 10))
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.sessions.first { $0.id == "fresh" }?.task == nil)
        #expect(store.sessions.first { $0.id == "remote" }?.task == nil)
        #expect(store.sessions.first { $0.id == "prompted" }?.task == "newer prompt")
    }

    @Test func readsTheLastRealPromptFromATranscript() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "transcript-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        {"type":"user","message":{"role":"user","content":"first prompt"}}
        {"type":"user","message":{"role":"user","content":[{"type":"text","text":"Research something on the web"}]}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]}}
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"42"}]}}
        {"type":"user","isMeta":true,"message":{"role":"user","content":"Caveat"}}
        {"type":"user","isSidechain":true,"message":{"role":"user","content":"subagent prompt"}}
        {"type":"user","message":{"role":"user","content":"<command-name>/model</command-name>"}}
        {"type":"user","message":{"role":"user","content":"[Request interrupted by user]"}}
        {"type":"user","isCompactSummary":true,"isVisibleInTranscriptOnly":true,"message":{"role":"user","content":"This session is being continued from a previous conversation"}}
        {"type":"ai-title","aiTitle":"Web research question"}

        """.write(to: url, atomically: true, encoding: .utf8)
        #expect(TranscriptReader.lastPrompt(at: url.path) == "Research something on the web")
        #expect(TranscriptReader.lastPrompt(at: "/nonexistent/transcript.jsonl") == nil)
    }

    @Test func localSessionsDisappearOnceTheirAgentProcessExits() async throws {
        let store = AgentSessionStore(localHost: { "mac" })
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "alive", prompt: "a", host: "mac", pid: 10))
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "remote", prompt: "b", host: "devbox", pid: 11))
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "unknown", prompt: "c", host: "mac"))
        let reply = Task { await store.handle(HookEvent(kind: .permissionRequest, sessionID: "exited", toolName: "Bash", toolInput: .object(["command": .string("ls")]), host: "mac", pid: 12)) }
        try await waitUntil { store.sessions.first?.pendingRequests.isEmpty == false }

        store.removeExitedSessions { $0 == 10 }
        #expect(await reply.value == .empty)
        #expect(Set(store.sessions.map(\.id)) == ["alive", "remote", "unknown"])
        #expect(ProcessMonitor.isRunning(getpid()))
    }

    @Test func questionsAreWithdrawnWhenTheMainAgentMovesOn() async throws {
        let store = AgentSessionStore()
        let question: JSONValue = .object(["questions": .array([.object(["question": .string("Color?"), "options": .array([.object(["label": .string("Red")])])])])])
        let first = Task { await store.handle(HookEvent(kind: .permissionRequest, sessionID: "a", toolName: "AskUserQuestion", toolInput: question)) }
        try await waitUntil { store.sessions.first?.pendingRequests.count == 1 }

        store.apply(HookEvent(kind: .preToolUse, sessionID: "a", toolName: "Read", agentType: "Explore"))
        store.apply(HookEvent(kind: .preToolUse, sessionID: "a", toolName: "AskUserQuestion", toolInput: question))
        #expect(store.sessions[0].pendingRequests.count == 1)
        store.apply(HookEvent(kind: .preToolUse, sessionID: "a", toolName: "Bash"))
        #expect(await first.value == .empty)
        #expect(store.sessions[0].pendingRequests.isEmpty)
        #expect(store.sessions[0].state == .working)

        let second = Task { await store.handle(HookEvent(kind: .permissionRequest, sessionID: "a", toolName: "AskUserQuestion", toolInput: question)) }
        try await waitUntil { store.sessions.first?.pendingRequests.count == 1 }
        let reformatted: JSONValue = .object(["questions": .array([.object(["question": .string("Color?"), "multiSelect": .bool(false), "options": .array([.object(["label": .string("Red")])])])]), "answers": .object(["Color?": .string("Red")])])
        store.apply(HookEvent(kind: .postToolUse, sessionID: "a", toolName: "AskUserQuestion", toolInput: reformatted))
        #expect(await second.value == .empty)
        #expect(store.sessions[0].pendingRequests.isEmpty)
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
    }

    @Test func thePillRingCountsSessionsByState() {
        let store = AgentSessionStore()
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "working", prompt: "a"))
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "done", prompt: "b"))
        store.apply(HookEvent(kind: .stop, sessionID: "done"))
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "second-done", prompt: "c"))
        store.apply(HookEvent(kind: .stop, sessionID: "second-done"))
        store.apply(HookEvent(kind: .sessionStart, sessionID: "ready"))
        #expect(store.pillStatus?.ring?.segments == [
            .init(value: 1, tint: SessionColors.workingTint),
            .init(value: 2, tint: SessionColors.finishedTint),
            .init(value: 1, tint: SessionColors.idleTint),
        ])

        store.apply(HookEvent(kind: .notification, sessionID: "working", message: "Pick one", notificationType: "elicitation_dialog"))
        #expect(store.pillStatus?.priority == .attention)
        #expect(store.pillStatus?.ring?.segments.first == .init(value: 1, tint: SessionColors.attentionTint))
    }

    @Test func statusChangesAreAnnouncedOncePreferringAttention() {
        var announcer = StatusAnnouncer()
        let store = AgentSessionStore()
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "a", cwd: "/p/alpha", prompt: "go"))
        #expect(announcer.announcement(for: store.sessions) == nil)

        store.apply(HookEvent(kind: .preToolUse, sessionID: "a", toolName: "Read"))
        #expect(announcer.announcement(for: store.sessions) == nil)

        store.apply(HookEvent(kind: .stop, sessionID: "a"))
        #expect(announcer.announcement(for: store.sessions)?.text == "alpha finished")
        #expect(announcer.announcement(for: store.sessions) == nil)

        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "b", cwd: "/p/beta", prompt: "go"))
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "a", prompt: "again"))
        _ = announcer.announcement(for: store.sessions)
        store.markInterrupted("a")
        #expect(announcer.announcement(for: store.sessions) == nil)

        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "a", prompt: "third"))
        store.apply(HookEvent(kind: .stop, sessionID: "a"))
        store.apply(HookEvent(kind: .notification, sessionID: "b", message: "Pick one", notificationType: "elicitation_dialog"))
        let announcement = announcer.announcement(for: store.sessions)
        #expect(announcement?.text == "beta · Pick one")
        #expect(announcement?.priority == .attention)

        store.apply(HookEvent(kind: .notification, sessionID: "b", notificationType: "idle_prompt"))
        #expect(store.sessions.first { $0.id == "b" }?.state == .needsAttention("Waiting for your input"))
        #expect(announcer.announcement(for: store.sessions) == nil)
    }

    @Test func theRingShowsOldFinishedSessionsAsIdle() {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let store = AgentSessionStore(now: { clock })
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "old", prompt: "a"))
        store.apply(HookEvent(kind: .stop, sessionID: "old"))
        clock = clock.addingTimeInterval(AgentSessionStore.finishedPillDuration + 1)
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "new", prompt: "b"))
        #expect(store.statusRing.segments == [
            .init(value: 1, tint: SessionColors.workingTint),
            .init(value: 1, tint: SessionColors.idleTint),
        ])
    }

    @Test func thePillNamesSessionsByTitleWhenTheyHaveOne() {
        let store = AgentSessionStore()
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "a", cwd: "/p/proj", prompt: "hi"))
        store.apply(HookEvent(kind: .stop, sessionID: "a", cwd: "/p/proj"))
        #expect(store.pillStatus?.text == "proj finished")
        store.apply(HookEvent(kind: .stop, sessionID: "a", cwd: "/p/proj", title: "islet-main"))
        #expect(store.pillStatus?.text == "islet-main finished")
    }

    @Test func sessionsCarryTheirCurrentTitle() {
        let store = AgentSessionStore(now: { Date(timeIntervalSince1970: 1_000_000) }, localHost: { "MacBook" })
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "a", cwd: "/one", prompt: "x"))
        #expect(store.sessions[0].title == nil)
        store.apply(HookEvent(kind: .preToolUse, sessionID: "a", toolName: "Read", title: "islet-main"))
        #expect(store.sessions[0].title == "islet-main")
        store.apply(HookEvent(kind: .preToolUse, sessionID: "a", toolName: "Read", title: "renamed"))
        #expect(store.sessions[0].title == "renamed")
        store.apply(HookEvent(kind: .stop, sessionID: "a"))
        #expect(store.sessions[0].title == "renamed")
    }

    @Test func idlePromptsDoNotHidePendingRequests() {
        let store = AgentSessionStore()
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "s", cwd: "/p", prompt: "x"))
        store.apply(HookEvent(kind: .permissionRequest, sessionID: "s", toolName: "Bash", toolInput: .object(["command": .string("ls")])))
        store.apply(HookEvent(kind: .notification, sessionID: "s", notificationType: "idle_prompt"))
        #expect(store.sessions[0].state == .needsAttention("Wants to $ ls"))
    }

    @Test func sessionsStayLocalWhenTheMacIsRenamedByTheNetwork() {
        var hostName = "MacBook"
        let store = AgentSessionStore(localHost: { hostName })
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "s", cwd: "/p", prompt: "x", host: "macbook"))
        #expect(store.sessions[0].isRemote == false)

        hostName = "student-net-dock-418"
        store.apply(HookEvent(kind: .preToolUse, sessionID: "s", toolName: "Read", host: "student-net-dock-418"))
        #expect(store.sessions[0].isRemote == false)

        store.apply(HookEvent(kind: .preToolUse, sessionID: "s", toolName: "Read", host: "macbook"))
        #expect(store.sessions[0].isRemote == true)
    }

    @Test func alertsOnceWhenASessionNeedsAttentionOrFinishes() async {
        let store = AgentSessionStore()
        var alerts: [AgentSessionStore.Alert] = []
        store.onAlert = { alerts.append($0) }
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "s", cwd: "/p", prompt: "x"))
        store.apply(HookEvent(kind: .preToolUse, sessionID: "s", toolName: "Read"))
        #expect(alerts.isEmpty)

        store.apply(HookEvent(kind: .notification, sessionID: "s", message: "Needs permission", notificationType: "permission_prompt"))
        store.apply(HookEvent(kind: .notification, sessionID: "s", message: "Waiting", notificationType: "elicitation_dialog"))
        #expect(alerts.count == 1)
        if case .needsAttention(let session) = alerts[0] {
            #expect(session.projectName == "p")
            #expect(session.state == .needsAttention("Needs permission"))
        } else {
            Issue.record("expected an attention alert")
        }

        store.apply(HookEvent(kind: .postToolUse, sessionID: "s", toolName: "Read"))
        store.apply(HookEvent(kind: .stop, sessionID: "s"))
        store.apply(HookEvent(kind: .stop, sessionID: "s"))
        #expect(alerts.count == 2)
        if case .finished(let session) = alerts[1] {
            #expect(session.task == "x")
        } else {
            Issue.record("expected a finished alert")
        }

        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "s", prompt: "y"))
        store.apply(HookEvent(kind: .permissionRequest, sessionID: "s", toolName: "Bash", toolInput: .object(["command": .string("ls")])))
        #expect(alerts.count == 3)
        store.apply(HookEvent(kind: .permissionRequest, sessionID: "s", toolName: "Bash", toolInput: .object(["command": .string("pwd")])))
        #expect(alerts.count == 3)
    }

    @Test func multipleSessionsAreCountedAndNewestFirst() {
        let store = AgentSessionStore()
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "a", cwd: "/x/one", prompt: "one"))
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "b", cwd: "/x/two", prompt: "two"))
        #expect(store.sessions.map(\.id) == ["b", "a"])
        #expect(store.pillStatus?.text == "2 agents working")

        store.apply(HookEvent(kind: .notification, sessionID: "a", message: "Claude needs your permission", notificationType: "permission_prompt"))
        store.apply(HookEvent(kind: .permissionRequest, sessionID: "b", toolName: "Bash", toolInput: .object(["command": .string("rm -rf build")])))
        #expect(store.sessions.first { $0.id == "b" }?.state == .needsAttention("Wants to $ rm -rf build"))
        #expect(store.pillStatus?.text == "2 agents need you")

        store.dismiss("a")
        #expect(store.sessions.map(\.id) == ["b"])
    }

    @Test func permissionRequestsWaitForADecision() async throws {
        let store = AgentSessionStore()
        let event = HookEvent(kind: .permissionRequest, sessionID: "a", cwd: "/x/one", toolName: "Bash", toolInput: .object(["command": .string("rm -rf build")]))
        async let reply = store.handle(event)
        try await waitForPendingRequest(in: store)
        let request = try #require(store.sessions.first?.pendingRequest)
        #expect(request.kind == .permission(tool: "Bash", detail: "rm -rf build"))
        #expect(store.pillStatus?.text == "one needs you")

        store.decide(request.id, .allow)
        #expect(await reply.body == #"{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}"#)
        #expect(store.sessions.first?.pendingRequest == nil)
        #expect(store.sessions.first?.state == .working)

        async let denied = store.handle(event)
        try await waitForPendingRequest(in: store)
        store.decide(try #require(store.sessions.first?.pendingRequest?.id), .deny)
        #expect(await denied.body.contains(#""behavior":"deny""#))
        #expect(store.sessions.first?.activity == "Denied Bash")
    }

    @Test func questionsAreAnsweredThroughUpdatedInput() async throws {
        let store = AgentSessionStore()
        let input: JSONValue = .object([
            "questions": .array([
                .object(["question": .string("Which framework?"), "header": .string("Framework"), "options": .array([.object(["label": .string("React"), "description": .string("Popular")]), .object(["label": .string("Vue")])]), "multiSelect": .bool(false)]),
            ]),
        ])
        async let reply = store.handle(HookEvent(kind: .permissionRequest, sessionID: "a", toolName: "AskUserQuestion", toolInput: input))
        try await waitForPendingRequest(in: store)
        let request = try #require(store.sessions.first?.pendingRequest)
        #expect(request.kind == .question([PendingRequest.Question(text: "Which framework?", header: "Framework", options: [.init(label: "React", description: "Popular"), .init(label: "Vue")])]))
        #expect(store.sessions.first?.state == .needsAttention("Has a question"))

        store.decide(request.id, .answers(["Which framework?": "Vue"]))
        let body = await reply.body
        let output = try #require(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        let decision = try #require((output["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
        #expect(decision["behavior"] as? String == "allow")
        let updated = try #require(decision["updatedInput"] as? [String: Any])
        #expect((updated["questions"] as? [Any])?.count == 1)
        #expect(updated["answers"] as? [String: String] == ["Which framework?": "Vue"])
    }

    @Test func pendingRequestsAreWithdrawnWhenTheSessionMovesOn() async throws {
        let store = AgentSessionStore()
        let event = HookEvent(kind: .permissionRequest, sessionID: "a", toolName: "Bash", toolInput: .object(["command": .string("ls")]))
        async let reply = store.handle(event)
        try await waitForPendingRequest(in: store)
        #expect(store.sessions.first?.pendingRequest != nil)

        store.apply(HookEvent(kind: .notification, sessionID: "a", message: "Claude needs your permission", notificationType: "permission_prompt"))
        #expect(store.sessions.first?.pendingRequest != nil)
        #expect(store.sessions.first?.state == .needsAttention("Wants to $ ls"))
        store.apply(HookEvent(kind: .postToolUse, sessionID: "a", toolName: "Grep", toolInput: .object(["pattern": .string("x")])))
        #expect(store.sessions.first?.pendingRequest != nil)

        store.apply(HookEvent(kind: .stop, sessionID: "a"))
        #expect(await reply == .empty)
        #expect(store.sessions.first?.pendingRequest == nil)
        #expect(store.sessions.first?.state == .done)

        async let cancelled = store.handle(event)
        try await waitForPendingRequest(in: store)
        store.dismiss("a")
        #expect(await cancelled == .empty)

        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "a", prompt: "again"))
        let task = Task { await store.handle(event) }
        try await waitForPendingRequest(in: store)
        #expect(store.sessions.first?.pendingRequest != nil)
        task.cancel()
        #expect(await task.value == .empty)
        let deadline = ContinuousClock.now + .seconds(2)
        while store.sessions.first?.pendingRequest != nil {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
        #expect(store.sessions.first?.state == .interrupted)
    }

    @Test func interruptedTurnsLeaveTheWorkingStateUntilTheAgentContinues() async throws {
        let store = AgentSessionStore()
        var alerts: [AgentSessionStore.Alert] = []
        store.onAlert = { alerts.append($0) }
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "a", cwd: "/p", prompt: "x"))
        store.apply(HookEvent(kind: .preToolUse, sessionID: "a", toolName: "Read"))
        store.markInterrupted("a")
        #expect(store.sessions[0].state == .interrupted)
        #expect(store.sessions[0].activity == nil)
        #expect(store.pillStatus == nil)
        #expect(alerts.isEmpty)

        store.apply(HookEvent(kind: .notification, sessionID: "a", notificationType: "idle_prompt"))
        #expect(store.sessions[0].state == .interrupted)
        #expect(alerts.isEmpty)

        store.apply(HookEvent(kind: .postToolUse, sessionID: "a", toolName: "Read"))
        #expect(store.sessions[0].state == .interrupted)
        store.apply(HookEvent(kind: .preToolUse, sessionID: "a", toolName: "Read"))
        #expect(store.sessions[0].state == .working)

        let reply = Task { await store.handle(HookEvent(kind: .permissionRequest, sessionID: "a", toolName: "Bash", toolInput: .object(["command": .string("ls")]))) }
        try await waitForPendingRequest(in: store)
        store.markInterrupted("a")
        #expect(await reply.value == .empty)
        #expect(store.sessions[0].pendingRequests.isEmpty)
        #expect(store.sessions[0].state == .interrupted)

        store.apply(HookEvent(kind: .stop, sessionID: "a"))
        store.markInterrupted("a")
        #expect(store.sessions[0].state == .done)
        store.markInterrupted("unknown")
    }

    @Test func requestsThatTimeOutKeepAskingForAttention() async throws {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let store = AgentSessionStore(now: { clock })
        let task = Task { await store.handle(HookEvent(kind: .permissionRequest, sessionID: "a", toolName: "Bash", toolInput: .object(["command": .string("ls")]))) }
        try await waitForPendingRequest(in: store)
        clock += TimeInterval(HookServer.replyTimeout.components.seconds)
        task.cancel()
        #expect(await task.value == .empty)
        let deadline = ContinuousClock.now + .seconds(2)
        while store.sessions.first?.pendingRequest != nil {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
        #expect(store.sessions[0].state == .needsAttention("Waiting for your answer in the terminal"))
    }

    @Test func toolResultsWithdrawTheExactRequestBeforeASimilarOne() async throws {
        let store = AgentSessionStore()
        let whole: JSONValue = .object(["file_path": .string("/a")])
        let partial: JSONValue = .object(["file_path": .string("/a"), "limit": .number(10)])
        let first = Task { await store.handle(HookEvent(kind: .permissionRequest, sessionID: "a", toolName: "Read", toolInput: whole)) }
        try await waitForPendingRequest(in: store)
        let second = Task { await store.handle(HookEvent(kind: .permissionRequest, sessionID: "a", toolName: "Read", toolInput: partial)) }
        try await waitForPendingRequest(in: store, count: 2)

        store.apply(HookEvent(kind: .postToolUse, sessionID: "a", toolName: "Read", toolInput: partial))
        #expect(await second.value == .empty)
        #expect(store.sessions[0].pendingRequests.map(\.toolInput) == [whole])
        store.apply(HookEvent(kind: .stop, sessionID: "a"))
        #expect(await first.value == .empty)
    }

    @Test func questionsAnsweredInTheTerminalAreWithdrawnWhenTheToolFinishes() async throws {
        let store = AgentSessionStore()
        let question: JSONValue = .object(["questions": .array([.object(["question": .string("Color?"), "options": .array([.object(["label": .string("Red")])])])])])
        let reply = Task { await store.handle(HookEvent(kind: .permissionRequest, sessionID: "a", toolName: "AskUserQuestion", toolInput: question)) }
        try await waitForPendingRequest(in: store)

        guard case .object(var answered) = question else { return }
        answered["answers"] = .object(["Color?": .string("Red")])
        answered["annotations"] = .object([:])
        store.apply(HookEvent(kind: .postToolUse, sessionID: "a", toolName: "AskUserQuestion", toolInput: .object(answered)))
        #expect(await reply.value == .empty)
        #expect(store.sessions[0].pendingRequests.isEmpty)
        #expect(store.sessions[0].state == .working)

        let bash = Task { await store.handle(HookEvent(kind: .permissionRequest, sessionID: "a", toolName: "Bash", toolInput: .object(["command": .string("ls"), "description": .string("List")]))) }
        try await waitForPendingRequest(in: store)
        store.apply(HookEvent(kind: .postToolUse, sessionID: "a", toolName: "Bash", toolInput: .object(["command": .string("ls -la"), "description": .string("List")])))
        #expect(store.sessions[0].pendingRequests.count == 1)
        store.apply(HookEvent(kind: .stop, sessionID: "a"))
        #expect(await bash.value == .empty)
    }

    func waitForPendingRequest(in store: AgentSessionStore, count: Int = 1) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while (store.sessions.first?.pendingRequests.count ?? 0) < count {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
    }

    @Test func concurrentRequestsAreQueuedAndAnsweredIndividually() async throws {
        let store = AgentSessionStore()
        let first = HookEvent(kind: .permissionRequest, sessionID: "a", toolName: "Bash", toolInput: .object(["command": .string("ls")]))
        let second = HookEvent(kind: .permissionRequest, sessionID: "a", toolName: "Edit", toolInput: .object(["file_path": .string("/x/a.swift")]))
        async let firstReply = store.handle(first)
        try await waitForPendingRequest(in: store)
        async let secondReply = store.handle(second)
        try await waitForPendingRequest(in: store, count: 2)
        let requests = try #require(store.sessions.first?.pendingRequests)
        #expect(requests.map(\.toolName) == ["Bash", "Edit"])
        #expect(store.sessions.first?.state == .needsAttention("Wants to $ ls"))

        store.decide(UUID(), .allow)
        #expect(store.sessions.first?.pendingRequests.count == 2)

        store.decide(requests[1].id, .deny)
        #expect(await secondReply.body.contains("deny"))
        #expect(store.sessions.first?.pendingRequest?.toolName == "Bash")
        #expect(store.sessions.first?.state == .needsAttention("Wants to $ ls"))

        store.apply(HookEvent(kind: .postToolUse, sessionID: "a", toolName: "Bash", toolInput: .object(["command": .string("ls")])))
        #expect(await firstReply == .empty)
        #expect(store.sessions.first?.pendingRequests.isEmpty == true)
        #expect(store.sessions.first?.state == .working)
    }

    @Test func unsupportedToolsOnlyRaiseAttention() async throws {
        let store = AgentSessionStore()
        let reply = await store.handle(HookEvent(kind: .permissionRequest, sessionID: "a", toolName: "ExitPlanMode", toolInput: .object([:])))
        #expect(reply == .empty)
        #expect(store.sessions.first?.pendingRequests.isEmpty == true)
        #expect(store.sessions.first?.state == .needsAttention("Wants to ExitPlanMode"))
        let question = await store.handle(HookEvent(kind: .permissionRequest, sessionID: "a", toolName: "AskUserQuestion", toolInput: .object(["questions": .array([])])))
        #expect(question == .empty)
        #expect(store.sessions.first?.pendingRequests.isEmpty == true)
    }

    @Test func autoModePermissionRequestsAreLeftToTheAgent() async {
        let store = AgentSessionStore()
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "a", prompt: "Fix the build"))
        let reply = await store.handle(HookEvent(kind: .permissionRequest, sessionID: "a", toolName: "Bash", toolInput: .object(["command": .string("rm -rf build")]), permissionMode: "auto"))
        #expect(reply == .empty)
        #expect(store.sessions.first?.pendingRequests.isEmpty == true)
        #expect(store.sessions.first?.state == .working)
        #expect(store.sessions.first?.activity == "$ rm -rf build")
        let question = HookEvent(kind: .permissionRequest, sessionID: "a", toolName: "AskUserQuestion", toolInput: .object(["questions": .array([.object(["question": .string("Which?"), "options": .array([.object(["label": .string("A")])])])])]), permissionMode: "auto")
        async let answer = store.handle(question)
        try? await waitForPendingRequest(in: store)
        #expect(store.sessions.first?.state == .needsAttention("Has a question"))
        store.decide(store.sessions.first!.pendingRequests[0].id, .answers(["Which?": "A"]))
        #expect(await answer != .empty)
        store.apply(HookEvent(kind: .permissionRequest, sessionID: "a", toolName: "ExitPlanMode", toolInput: .object([:]), permissionMode: "auto"))
        #expect(store.sessions.first?.state == .needsAttention("Wants to ExitPlanMode"))
    }

    @Test func taskNotificationsNeitherWithdrawRequestsNorReviveDismissedSessions() async throws {
        let store = AgentSessionStore()
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "a", prompt: "Deploy"))
        async let reply = store.handle(HookEvent(kind: .permissionRequest, sessionID: "a", toolName: "Bash", toolInput: .object(["command": .string("make deploy")])))
        try await waitForPendingRequest(in: store)
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "a", prompt: "<task-notification>done</task-notification>"))
        #expect(store.sessions.first?.pendingRequests.count == 1)
        #expect(store.sessions.first?.state.requiresAttention == true)
        store.decide(store.sessions.first!.pendingRequests[0].id, .allow)
        #expect(await reply != .empty)

        store.dismiss("a")
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "a", prompt: "<task-notification>done</task-notification>"))
        #expect(store.sessions.isEmpty)
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "a", prompt: "Again"))
        #expect(store.sessions.count == 1)
    }

    @Test func subagentTaskNotificationsKeepTheOriginalTask() {
        let store = AgentSessionStore()
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "a", prompt: "Review the plugin"))
        store.apply(HookEvent(kind: .preToolUse, sessionID: "a", toolName: "Read", toolInput: .object(["file_path": .string("/p/Main.swift")]), agentType: "Explore"))
        #expect(store.sessions.first?.activity == "Explore: Read Main.swift")
        store.apply(HookEvent(kind: .stop, sessionID: "a"))
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "a", prompt: "<task-notification>\n<task-id>abc</task-id>"))
        #expect(store.sessions.first?.task == "Review the plugin")
        #expect(store.sessions.first?.state == .working)
    }

    @Test func notifiesOnEveryChange() {
        let store = AgentSessionStore()
        var changes = 0
        store.onChange = { changes += 1 }
        store.apply(HookEvent(kind: .sessionStart, sessionID: "a"))
        store.apply(HookEvent(kind: .sessionEnd, sessionID: "a"))
        store.dismiss("nope")
        #expect(changes == 2)
    }
}

@MainActor
struct MarkdownTextTests {
    @Test func splitsMarkdownIntoBlocks() {
        let blocks = MarkdownText.parse("# Title\n\nSome *text*\nthat wraps\n\n- one\n* two\n1. first\n```\nlet x = 1\n```\n")
        let expected: [MarkdownText.Block] = [
            .heading("Title", level: 1),
            .paragraph("Some *text* that wraps"),
            .bullet("one"),
            .bullet("two"),
            .numbered("first", number: "1"),
            .code("let x = 1"),
        ]
        #expect(blocks == expected)
    }
}

@MainActor
struct AgentsPluginSizingTests {
    @Test func contentGrowsWithSessionsUpToAScrollingMaximum() {
        func sessions(_ count: Int) -> [AgentSession] {
            (0..<count).map { AgentSession(id: "\($0)", agent: .claudeCode, host: nil, cwd: nil, task: nil, activity: nil, state: .working, startedAt: .now, turnStartedAt: .now, updatedAt: .now) }
        }
        #expect(AgentsPlugin.contentSize(for: [], expanded: [], showsUsage: false) == CGSize(width: 520, height: 130))
        #expect(AgentsPlugin.contentSize(for: sessions(1), expanded: [], showsUsage: false) == CGSize(width: 520, height: 92))
        #expect(AgentsPlugin.contentSize(for: sessions(2), expanded: [], showsUsage: false) == CGSize(width: 520, height: 166))
        #expect(AgentsPlugin.contentSize(for: sessions(4), expanded: [], showsUsage: false) == AgentsPlugin.contentSize(for: sessions(9), expanded: [], showsUsage: false))
        let usage = AgentsPlugin.usageBarHeight + AgentsPlugin.rowSpacing
        #expect(AgentsPlugin.contentSize(for: [], expanded: [], showsUsage: true).height == 130 + usage)
        #expect(AgentsPlugin.contentSize(for: sessions(1), expanded: [], showsUsage: true).height == 92 + usage)
        #expect(AgentsPlugin.contentSize(for: sessions(9), expanded: [], showsUsage: true).height == AgentsPlugin.maxContentHeight + usage)
    }

    @Test func pendingRequestsMakeRowsTaller() {
        var session = AgentSession(id: "a", agent: .claudeCode, host: nil, cwd: nil, task: nil, activity: nil, state: .working, startedAt: .now, turnStartedAt: .now, updatedAt: .now)
        let plain = AgentsPlugin.contentSize(for: [session], expanded: [], showsUsage: false).height
        session.pendingRequests = [PendingRequest(toolName: "Bash", toolInput: .object(["command": .string("ls")]))!]
        let permission = AgentsPlugin.contentSize(for: [session], expanded: [], showsUsage: false).height
        #expect(permission > plain)
        session.pendingRequests = [PendingRequest(toolName: "AskUserQuestion", toolInput: .object([
            "questions": .array([
                .object(["question": .string("Which?"), "options": .array([.object(["label": .string("A")]), .object(["label": .string("B")]), .object(["label": .string("C")])])]),
                .object(["question": .string("Multi?"), "multiSelect": .bool(true), "options": .array([.object(["label": .string("X")])])]),
            ]),
        ]))!]
        let question = AgentsPlugin.contentSize(for: [session], expanded: [], showsUsage: false).height
        #expect(question > permission)
        #expect(question <= AgentsPlugin.maxContentHeight)
    }

    @Test func expandedRowsGrowWithActivityAndPlan() {
        var session = AgentSession(id: "a", agent: .claudeCode, host: nil, cwd: nil, task: nil, activity: nil, state: .working, startedAt: .now, turnStartedAt: .now, updatedAt: .now)
        let collapsed = AgentsPlugin.contentSize(for: [session], expanded: [], showsUsage: false).height
        let empty = AgentsPlugin.contentSize(for: [session], expanded: ["a"], showsUsage: false).height
        #expect(empty > collapsed)
        session.activities = (0..<3).map { _ in ActivityEntry(event: HookEvent(kind: .preToolUse, sessionID: "a", toolName: "Read"), at: .now, isComplete: true) }
        let withActivity = AgentsPlugin.contentSize(for: [session], expanded: ["a"], showsUsage: false).height
        #expect(withActivity == empty + 2 * AgentsPlugin.activityEntryHeight)
        session.plan = "# Plan"
        #expect(AgentsPlugin.contentSize(for: [session], expanded: ["a"], showsUsage: false).height > withActivity)
    }
}

struct UsageTests {
    @Test func decodesUsageWindowsAndSkipsMissingOnes() throws {
        let usage = try ClaudeUsage.decode(Data(#"{"five_hour":{"utilization":11.5,"resets_at":"2026-09-20T18:00:00.5+00:00"},"seven_day":{"utilization":2,"resets_at":"2026-09-27T09:00:00Z"},"seven_day_opus":null}"#.utf8))
        #expect(usage.fiveHour?.utilization == 11.5)
        #expect(usage.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_789_927_200.5))
        #expect(usage.sevenDay?.utilization == 2)
        #expect(usage.sevenDay?.resetsAt == Date(timeIntervalSince1970: 1_790_499_600))
        #expect(try ClaudeUsage.decode(Data("{}".utf8)).isEmpty)
        #expect(throws: UsageError.unexpectedResponse) { try ClaudeUsage.decode(Data("[]".utf8)) }
    }

    @Test func readsTheAccessTokenFromTheLoginFile() {
        #expect(ClaudeCredentials.accessToken(from: Data(#"{"claudeAiOauth":{"accessToken":"token-from-test","expiresAt":1}}"#.utf8)) == "token-from-test")
        #expect(ClaudeCredentials.accessToken(from: Data("{}".utf8)) == nil)
    }

    @MainActor
    @Test func monitorSendsTheBearerTokenAndReportsFailures() async throws {
        let requests = Requests()
        let token = Box(value: "token-from-test")
        let status = StatusBox()
        let monitor = UsageMonitor(isEnabled: true, accessToken: { token.value }, load: { request in
            await requests.record(request)
            return (Data(#"{"five_hour":{"utilization":40,"resets_at":null}}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: status.value, httpVersion: nil, headerFields: nil)!)
        })
        monitor.refresh(force: true)
        try await waitUntil { monitor.usage != nil }
        #expect(monitor.usage == ClaudeUsage(fiveHour: UsageWindow(utilization: 40, resetsAt: nil), sevenDay: nil))
        let request = await requests.all.first
        #expect(request?.url == UsageMonitor.endpoint)
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer token-from-test")
        #expect(request?.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")

        monitor.refresh()
        try await Task.sleep(for: .milliseconds(50))
        #expect(await requests.all.count == 1)

        status.value = 503
        monitor.refresh(force: true)
        try await waitUntil { monitor.error != nil }
        #expect(monitor.error == UsageError.status(503).errorDescription)
        #expect(monitor.usage != nil)

        status.value = 200
        monitor.refresh(force: true)
        try await waitUntil { monitor.error == nil }

        token.value = nil
        monitor.refresh(force: true)
        try await waitUntil { monitor.usage == nil }
        #expect(monitor.error == UsageError.notLoggedIn.errorDescription)

        monitor.isEnabled = false
        #expect(monitor.error == nil)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out")
    }

    private actor Requests {
        var all: [URLRequest] = []
        func record(_ request: URLRequest) { all.append(request) }
    }

    private final class Box: @unchecked Sendable {
        var value: String?
        init(value: String?) { self.value = value }
    }

    private final class StatusBox: @unchecked Sendable {
        var value = 200
    }
}

@MainActor
struct InterruptionMonitorTests {
    static let interrupted = #"{"parentUuid":"a","isSidechain":false,"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]},"uuid":"b"}"#
    static let deniedTool = #"{"isSidechain":false,"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}"#
    static let assistantQuote = #"{"isSidechain":false,"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#
    static let promptQuote = #"{"isSidechain":false,"type":"user","message":{"role":"user","content":"Why does [Request interrupted by user] appear?"}}"#
    static let sidechain = #"{"isSidechain":true,"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#
    static let progress = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Working on it"}]}}"#

    @Test func recognizesOnlyTheAgentsOwnInterruptionEntries() {
        #expect(InterruptionMonitor.containsInterruption(Data((Self.progress + "\n" + Self.interrupted + "\n").utf8)))
        #expect(InterruptionMonitor.containsInterruption(Data((Self.deniedTool + "\n").utf8)))
        #expect(!InterruptionMonitor.containsInterruption(Data((Self.assistantQuote + "\n").utf8)))
        #expect(!InterruptionMonitor.containsInterruption(Data((Self.promptQuote + "\n").utf8)))
        #expect(!InterruptionMonitor.containsInterruption(Data((Self.sidechain + "\n").utf8)))
        #expect(!InterruptionMonitor.containsInterruption(Data("[Request interrupted by user] not json\n".utf8)))
    }

    @Test func reportsInterruptionsAppendedWhileASessionWorks() throws {
        let transcript = FileManager.default.temporaryDirectory.appending(path: "InterruptionMonitorTests.\(UUID().uuidString).jsonl")
        try Data((Self.interrupted + "\n").utf8).write(to: transcript)
        defer { try? FileManager.default.removeItem(at: transcript) }
        func append(_ text: String) throws {
            let handle = try FileHandle(forWritingTo: transcript)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
            try handle.close()
        }

        var interrupted: [String] = []
        let monitor = InterruptionMonitor { interrupted.append($0) }
        let store = AgentSessionStore()
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "local", transcriptPath: transcript.path, prompt: "x"))
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "remote", transcriptPath: transcript.path, prompt: "x", host: "elsewhere"))
        store.apply(HookEvent(kind: .stop, sessionID: "finished", transcriptPath: transcript.path))
        monitor.track(store.sessions)

        monitor.poll()
        #expect(interrupted.isEmpty)

        try append(Self.progress + "\n")
        monitor.poll()
        #expect(interrupted.isEmpty)

        try append(String(Self.interrupted.prefix(40)))
        monitor.poll()
        #expect(interrupted.isEmpty)

        try append(String(Self.interrupted.dropFirst(40)) + "\n")
        monitor.poll()
        #expect(interrupted == ["local"])

        monitor.poll()
        #expect(interrupted == ["local"])

        try Data((Self.progress + "\n").utf8).write(to: transcript)
        monitor.poll()
        try append(Self.interrupted + "\n")
        monitor.poll()
        #expect(interrupted == ["local", "local"])

        store.markInterrupted("local")
        monitor.track(store.sessions)
        try append(Self.interrupted + "\n")
        monitor.poll()
        #expect(interrupted == ["local", "local"])
    }

    @Test func anInterruptionBeforeTheNextPromptDoesNotEndTheNewTurn() throws {
        let transcript = FileManager.default.temporaryDirectory.appending(path: "InterruptionMonitorTests.\(UUID().uuidString).jsonl")
        try Data((Self.progress + "\n").utf8).write(to: transcript)
        defer { try? FileManager.default.removeItem(at: transcript) }
        var clock = Date(timeIntervalSince1970: 1_000_000)
        var interrupted: [String] = []
        let monitor = InterruptionMonitor { interrupted.append($0) }
        let store = AgentSessionStore(now: { clock })
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "s", transcriptPath: transcript.path, prompt: "first"))
        monitor.track(store.sessions)

        let handle = try FileHandle(forWritingTo: transcript)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((Self.interrupted + "\n").utf8))
        try handle.close()
        clock += 1
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "s", prompt: "second"))
        monitor.track(store.sessions)
        monitor.poll()

        #expect(interrupted.isEmpty)
        #expect(store.sessions[0].state == .working)
    }
}

struct HookInstallerTests {
    func makeInstaller(agent: AgentSession.Agent = .claudeCode) throws -> HookInstaller {
        let directory = FileManager.default.temporaryDirectory.appending(path: "AgentsPluginTests." + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return HookInstaller(agent: agent, directory: directory, port: 7365, token: "deadbeef")
    }

    @Test func installsCodexHooksIntoHooksJSON() throws {
        let installer = try makeInstaller(agent: .codex)
        #expect(installer.settingsURL.lastPathComponent == "hooks.json")
        #expect(!installer.events.contains("Notification"))
        try installer.install()
        #expect(installer.isInstalled)
        #expect(try String(contentsOf: installer.scriptURL, encoding: .utf8).contains("-H \"X-Islet-Agent: codex\""))
        let hooks = (try JSONSerialization.jsonObject(with: Data(contentsOf: installer.settingsURL)) as? [String: Any])?["hooks"] as? [String: Any]
        #expect(Set(hooks?.keys.map { $0 } ?? []) == Set(installer.events))
        try installer.uninstall()
        #expect(!installer.isInstalled)
    }

    @Test func scriptForwardsThePayloadWithTheSessionTitleFromItsTranscript() throws {
        let installer = try makeInstaller()
        try installer.install()
        let transcript = installer.directory.appending(path: "transcript.jsonl")
        try """
        {"type":"custom-title","customTitle":"first","sessionId":"a"}
        {"type":"user","message":"hello"}
        {"type":"custom-title","customTitle":"islet main","sessionId":"a"}
        {"type":"ai-title","aiTitle":"generated later","sessionId":"a"}
        {"type":"ai-title","aiTitle":"quoted \\"ai\\" title","sessionId":"a"}

        """.write(to: transcript, atomically: true, encoding: .utf8)
        let capture = installer.directory.appending(path: "curl-call")
        let fakeCurl = installer.directory.appending(path: "curl")
        try "#!/bin/sh\nprintf '%s\\n' \"$@\" > '\(capture.path)'\ncat >> '\(capture.path)'\nfor a in \"$@\"; do case \"$a\" in @*) cat \"${a#@}\" >> '\(capture.path)';; esac; done\n".write(to: fakeCurl, atomically: true, encoding: .utf8)
        let cwd = installer.directory.appending(path: "project")
        try FileManager.default.createDirectory(at: cwd.appending(path: "db"), withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCurl.path)
        let payload = #"{"session_id":"a","hook_event_name":"Stop","transcript_path":"\#(transcript.path)"}"#

        let path = installer.directory.path + ":/usr/bin:/bin"
        let environments: [(exists: Bool, title: String, terminal: String, environment: [String: String])] = [
            (true, "islet main", "com.example.terminal", ["__CFBundleIdentifier": "com.example.terminal", "TERM_PROGRAM": "fallback"]),
            (true, "islet main", "cursor", ["TERM_PROGRAM": "vscode", "VSCODE_GIT_ASKPASS_MAIN": "/home/me/.cursor-server/bin/abc/extensions/git/dist/askpass-main.js"]),
            (true, "islet main", "vscode", ["TERM_PROGRAM": "vscode", "VSCODE_GIT_ASKPASS_MAIN": "/home/me/.vscode-server/bin/abc/extensions/git/dist/askpass-main.js"]),
            (false, "", "fallback", ["TERM_PROGRAM": "fallback"]),
        ]
        for (transcriptExists, expectedTitle, expectedTerminal, environment) in environments {
            if !transcriptExists { try FileManager.default.removeItem(at: transcript) }
            let process = Process()
            process.executableURL = URL(filePath: "/bin/sh")
            process.arguments = [installer.scriptURL.path]
            process.environment = environment.merging(["PATH": path]) { $1 }
            process.currentDirectoryURL = cwd
            let input = Pipe()
            process.standardInput = input
            try process.run()
            input.fileHandleForWriting.write(Data(payload.utf8))
            try input.fileHandleForWriting.close()
            process.waitUntilExit()
            let call = try String(contentsOf: capture, encoding: .utf8).components(separatedBy: "\n")
            #expect(call.contains("X-Islet-Title: \(expectedTitle)"))
            #expect(call.contains("X-Islet-Agent: claude-code"))
            #expect(call.contains("X-Islet-Terminal: \(expectedTerminal)"))
            #expect(call.filter { $0.contains("deadbeef") } == ["header = \"Authorization: Bearer deadbeef\""])
            #expect(call.contains { $0.hasPrefix("X-Islet-TTY: ") && !$0.contains("/dev/db") })
            #expect(call.last == payload)
        }
    }

    @Test func scriptFallsBackToTheGeneratedTitleAndReportsTheAgentProcess() throws {
        let installer = try makeInstaller()
        try installer.install()
        let transcript = installer.directory.appending(path: "transcript.jsonl")
        try """
        {"type":"ai-title","aiTitle":"first guess","sessionId":"a"}
        {"type":"user","message":"hello"}
        {"type":"ai-title","aiTitle":"fix \\"hook\\" titles \\\\ now","sessionId":"a"}

        """.write(to: transcript, atomically: true, encoding: .utf8)
        let capture = installer.directory.appending(path: "curl-call")
        let fakeCurl = installer.directory.appending(path: "curl")
        try "#!/bin/sh\nprintf '%s\\n' \"$@\" > '\(capture.path)'\n".write(to: fakeCurl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCurl.path)
        let payload = #"{"session_id":"a","hook_event_name":"Stop","transcript_path":"\#(transcript.path)"}"#

        let agent = installer.directory.appending(path: "claude")
        try FileManager.default.createSymbolicLink(at: agent, withDestinationURL: URL(filePath: "/bin/bash"))
        let process = Process()
        process.executableURL = agent
        process.arguments = ["-c", "/usr/bin/time sh \"$0\" 2>/dev/null; true", installer.scriptURL.path]
        process.environment = ["PATH": installer.directory.path + ":/usr/bin:/bin"]
        let input = Pipe()
        process.standardInput = input
        try process.run()
        input.fileHandleForWriting.write(Data(payload.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        let call = try String(contentsOf: capture, encoding: .utf8).components(separatedBy: "\n")
        #expect(call.contains(#"X-Islet-Title: fix "hook" titles \ now"#))
        #expect(call.contains("X-Islet-PID: \(process.processIdentifier)"))
    }

    @Test func killingTheScriptAbortsTheRequestAndCleansUp() throws {
        let installer = try makeInstaller()
        try installer.install()
        let capture = installer.directory.appending(path: "curl-call")
        let fakeCurl = installer.directory.appending(path: "curl")
        try "#!/bin/sh\nfor a in \"$@\"; do case \"$a\" in @*) body=\"${a#@}\";; esac; done\nprintf '%s\\n%s\\n' \"$$\" \"$body\" > '\(capture.path)'\nexec sleep 30\n".write(to: fakeCurl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCurl.path)

        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = [installer.scriptURL.path, "600"]
        process.environment = ["PATH": installer.directory.path + ":/usr/bin:/bin"]
        let input = Pipe()
        process.standardInput = input
        try process.run()
        input.fileHandleForWriting.write(Data(#"{"session_id":"a","hook_event_name":"PermissionRequest"}"#.utf8))
        try input.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(10)
        var call: [String] = []
        while call.count < 2, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
            call = ((try? String(contentsOf: capture, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        }
        let request = try #require(Int32(call.first ?? ""))
        #expect(FileManager.default.fileExists(atPath: call[1]))

        kill(process.processIdentifier, SIGTERM)
        process.waitUntilExit()
        let exitDeadline = Date().addingTimeInterval(5)
        while kill(request, 0) == 0, Date() < exitDeadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        #expect(kill(request, 0) != 0)
        #expect(!FileManager.default.fileExists(atPath: call[1]))
    }

    @Test func installsScriptAndMergesHooksWithoutTouchingOtherSettings() throws {
        let installer = try makeInstaller()
        let existing = """
        {"model":"opus","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo hi"}]}]}}
        """
        try existing.write(to: installer.settingsURL, atomically: true, encoding: .utf8)
        #expect(!installer.isInstalled)

        try installer.install()
        #expect(installer.isInstalled)

        let settings = try JSONSerialization.jsonObject(with: Data(contentsOf: installer.settingsURL)) as! [String: Any]
        #expect(settings["model"] as? String == "opus")
        let hooks = settings["hooks"] as! [String: Any]
        #expect(Set(hooks.keys) == Set(installer.events))
        let preToolUse = hooks["PreToolUse"] as! [[String: Any]]
        #expect(preToolUse.count == 2)
        #expect((preToolUse[0]["matcher"] as? String) == "Bash")
        let permissionHook = ((hooks["PermissionRequest"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]])[0]
        #expect(permissionHook["command"] as? String == "'" + installer.scriptURL.path + "' 600")
        #expect(permissionHook["timeout"] as? Int == 605)
        #expect((((preToolUse[1]["hooks"] as! [[String: Any]])[0])["timeout"] as? Int) == 10)
        let sessionEnd = ((hooks["SessionEnd"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]])[0]
        #expect(sessionEnd["timeout"] as? Int == 3)
        #expect(sessionEnd["command"] as? String == "'" + installer.scriptURL.path + "' 2")

        let script = try String(contentsOf: installer.scriptURL, encoding: .utf8)
        #expect(script.contains("Bearer deadbeef"))
        #expect(script.contains("127.0.0.1:7365/hook"))
        #expect(script.contains(#"-H "X-Islet-Terminal: $terminal""#))
        #expect(script.contains(#"-H "X-Islet-TTY: $tty""#))
        let permissions = try FileManager.default.attributesOfItem(atPath: installer.scriptURL.path)[.posixPermissions] as! Int
        #expect(permissions == 0o700)
        #expect(try String(contentsOf: installer.settingsURL, encoding: .utf8).contains("\"command\" : \"'/"))

        try installer.install()
        #expect((try JSONSerialization.jsonObject(with: Data(contentsOf: installer.settingsURL)) as! [String: Any])["hooks"].map { ($0 as! [String: Any])["PreToolUse"] as! [[String: Any]] }?.count == 2)

        try installer.uninstall()
        #expect(!installer.isInstalled)
        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: installer.settingsURL)) as! [String: Any]
        let afterHooks = after["hooks"] as! [String: Any]
        #expect(Array(afterHooks.keys) == ["PreToolUse"])
        #expect(!FileManager.default.fileExists(atPath: installer.scriptURL.path))
    }

    @Test func installsIntoMissingSettingsFile() throws {
        let installer = try makeInstaller()
        try installer.install()
        #expect(installer.isInstalled)
        try installer.uninstall()
        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: installer.settingsURL)) as! [String: Any]
        #expect(after.isEmpty)
    }

    @Test func refusesToOverwriteSettingsThatAreNotAnObject() throws {
        let installer = try makeInstaller()
        try "[1, 2]".write(to: installer.settingsURL, atomically: true, encoding: .utf8)
        #expect(throws: HookInstaller.UnreadableSettings.self) { try installer.install() }
        #expect(try String(contentsOf: installer.settingsURL, encoding: .utf8) == "[1, 2]")
    }

    @Test func remoteInstallScriptReproducesTheLocalInstallation() throws {
        let installer = try makeInstaller()
        let codex = try makeInstaller(agent: .codex)
        let remote = FileManager.default.temporaryDirectory.appending(path: "AgentsPluginTests.remote." + UUID().uuidString)
        let remoteCodex = remote.appending(path: "codex")
        try FileManager.default.createDirectory(at: remoteCodex, withIntermediateDirectories: true)
        try #"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo done"}]}]}}"#.write(to: remote.appending(path: "settings.json"), atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.environment = ["HOME": "/nonexistent", "PATH": "/usr/bin:/bin", "CLAUDE_CONFIG_DIR": remote.path, "CODEX_HOME": remoteCodex.path]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = Pipe()
        try process.run()
        input.fileHandleForWriting.write(Data(HookInstaller.remoteInstallScript(for: [installer, codex]).utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        let remoteInstaller = HookInstaller(directory: remote, port: 7365, token: "deadbeef")
        #expect(remoteInstaller.isInstalled)
        #expect(HookInstaller(agent: .codex, directory: remoteCodex, port: 7365, token: "deadbeef").isInstalled)
        let settings = try JSONSerialization.jsonObject(with: Data(contentsOf: remoteInstaller.settingsURL)) as? [String: Any]
        #expect(settings?["model"] as? String == "opus")
        let stop = (settings?["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
        #expect(stop?.count == 2)
        let command = ((stop?.last?["hooks"] as? [[String: Any]])?.first?["command"] as? String) ?? ""
        #expect(command == "'\(remoteInstaller.scriptURL.path)'")
        #expect(installer.remoteInstallCommand.contains("Bearer deadbeef"))
        #expect(installer.remoteInstallCommand.contains("127.0.0.1:7365/install"))
        #expect(installer.sshConfigSnippet == "RemoteForward 7365 127.0.0.1:7365")
    }

    @Test func outdatedScriptCountsAsNotInstalled() throws {
        let installer = try makeInstaller()
        try installer.install()
        try "#!/bin/sh\nexit 0\n".write(to: installer.scriptURL, atomically: true, encoding: .utf8)
        #expect(!installer.isInstalled)
        #expect(installer.needsUpgrade)
    }

    @Test func outdatedHookEntriesCountAsNotInstalled() throws {
        let installer = try makeInstaller()
        try installer.install()
        var settings = try JSONSerialization.jsonObject(with: Data(contentsOf: installer.settingsURL)) as! [String: Any]
        var hooks = settings["hooks"] as! [String: Any]
        hooks["SessionEnd"] = [["hooks": [["type": "command", "command": "'" + installer.scriptURL.path + "'", "timeout": 10]]]]
        settings["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: settings).write(to: installer.settingsURL)
        #expect(!installer.isInstalled)
        #expect(installer.needsUpgrade)
        try installer.install()
        #expect(installer.isInstalled)
    }
}

struct HTTPRequestTests {
    @Test func parsesPostWithBodyAndWaitsForCompleteBody() {
        let head = "POST /hook HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nAuthorization: Bearer t\r\n\r\n"
        #expect(HTTPRequest.parse(Data((head + "ab").utf8), maxBodySize: 100) == .incomplete)
        #expect(HTTPRequest.parse(Data("POST /hook HTTP/1.1\r\nHo".utf8), maxBodySize: 100) == .incomplete)
        guard case .complete(let request) = HTTPRequest.parse(Data((head + "abcde").utf8), maxBodySize: 100) else {
            Issue.record("expected a complete request")
            return
        }
        #expect(request.method == "POST")
        #expect(request.path == "/hook")
        #expect(request.bearerToken == "t")
        #expect(request.body == Data("abcde".utf8))
    }

    @Test func rejectsMalformedAndOversizedRequests() {
        #expect(HTTPRequest.parse(Data("POST /hook HTTP/1.1\r\nContent-Length: -3\r\n\r\n".utf8), maxBodySize: 100) == .invalid)
        #expect(HTTPRequest.parse(Data("POST /hook HTTP/1.1\r\nContent-Length: abc\r\n\r\n".utf8), maxBodySize: 100) == .invalid)
        #expect(HTTPRequest.parse(Data("GARBAGE\r\n\r\n".utf8), maxBodySize: 100) == .invalid)
        #expect(HTTPRequest.parse(Data("POST /hook HTTP/1.1\r\nno colon\r\n\r\n".utf8), maxBodySize: 100) == .invalid)
        #expect(HTTPRequest.parse(Data("POST /hook HTTP/1.1\r\nContent-Length: 101\r\n\r\n".utf8), maxBodySize: 100) == .tooLarge(remainingBody: 101))
        #expect(HTTPRequest.parse(Data(repeating: UInt8(ascii: "a"), count: HTTPRequest.maxHeaderSize + 1), maxBodySize: 100) == .invalid)
    }

    @Test func serializesResponse() {
        let response = HTTPResponse.json(401, "{}")
        #expect(String(decoding: response.serialized, as: UTF8.self).hasPrefix("HTTP/1.1 401 Unauthorized\r\n"))
        #expect(String(decoding: response.serialized, as: UTF8.self).hasSuffix("\r\n\r\n{}"))
    }
}

@Suite(.serialized)
struct HookServerTests {
    @Test func receivesAuthorizedEventsAndRejectsOthers() async throws {
        let received = Received()
        let port = try freePort()
        let server = HookServer(port: port, token: "secret", installScript: "#!/bin/sh\necho installed\n") { event in
            await received.add(event)
            return .empty
        }
        try await server.start()
        defer { Task { await server.stop() } }

        let second = HookServer(port: port, token: "other") { _ in .empty }
        await #expect(throws: (any Error).self) { try await second.start() }
        #expect(await !second.isListening)

        let url = URL(string: "http://127.0.0.1:\(port)/hook")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        request.setValue("codex", forHTTPHeaderField: "X-Islet-Agent")
        request.setValue("devbox", forHTTPHeaderField: "X-Islet-Host")
        request.setValue("ghostty", forHTTPHeaderField: "X-Islet-Terminal")
        request.setValue("/dev/ttys004", forHTTPHeaderField: "X-Islet-TTY")
        request.setValue("islet-main", forHTTPHeaderField: "X-Islet-Title")
        request.httpBody = Data(#"{"session_id":"s","hook_event_name":"Stop"}"#.utf8)
        let (body, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(body == Data("{}".utf8))
        #expect(await received.events == [HookEvent(kind: .stop, sessionID: "s", agent: .codex, host: "devbox", terminal: TerminalApp(identifier: "com.mitchellh.ghostty"), tty: "/dev/ttys004", title: "islet-main")])

        request.setValue("Bearer wrong", forHTTPHeaderField: "Authorization")
        let (_, unauthorized) = try await URLSession.shared.data(for: request)
        #expect((unauthorized as? HTTPURLResponse)?.statusCode == 401)

        var install = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/install")!)
        install.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        let (script, installResponse) = try await URLSession.shared.data(for: install)
        #expect((installResponse as? HTTPURLResponse)?.statusCode == 200)
        #expect((installResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") == "text/plain; charset=utf-8")
        #expect(String(decoding: script, as: UTF8.self) == "#!/bin/sh\necho installed\n")
        install.setValue("Bearer wrong", forHTTPHeaderField: "Authorization")
        let (_, installDenied) = try await URLSession.shared.data(for: install)
        #expect((installDenied as? HTTPURLResponse)?.statusCode == 401)

        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("not json".utf8)
        let (_, bad) = try await URLSession.shared.data(for: request)
        #expect((bad as? HTTPURLResponse)?.statusCode == 400)

        request.httpBody = Data(repeating: UInt8(ascii: "x"), count: HookServer.maxBodySize + 1)
        let (_, large) = try await URLSession.shared.data(for: request)
        #expect((large as? HTTPURLResponse)?.statusCode == 413)
        #expect(await received.events.count == 1)

        await server.stop()
        #expect(await !server.isListening)
        try await server.start()
        request.httpBody = Data(#"{"session_id":"t","hook_event_name":"Stop"}"#.utf8)
        let (_, again) = try await URLSession.shared.data(for: request)
        #expect((again as? HTTPURLResponse)?.statusCode == 200)
        #expect(await received.events.count == 2)
    }

    @Test func repliesWaitForTheHandlerAndCancelWhenTheClientLeaves() async throws {
        let gate = Gate()
        let port = try freePort()
        let server = HookServer(port: port, token: "secret") { _ in
            await gate.wait()
        }
        try await server.start()
        defer { Task { await server.stop() } }

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/hook")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 1
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"Bash"}"#.utf8)
        await #expect(throws: (any Error).self) { try await URLSession.shared.data(for: request) }
        let deadline = ContinuousClock.now + .seconds(2)
        while await gate.cancelled == 0 {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }

        request.timeoutInterval = 10
        let final = request
        async let response = URLSession.shared.data(for: final)
        try await Task.sleep(for: .milliseconds(200))
        await gate.open(with: HookReply(body: #"{"ok":true}"#))
        let (body, _) = try await response
        #expect(body == Data(#"{"ok":true}"#.utf8))

        let dropped = Task { try await URLSession.shared.data(for: final) }
        try await Task.sleep(for: .milliseconds(200))
        await server.stop()
        await #expect(throws: (any Error).self) { try await dropped.value }
        #expect(await gate.cancelled == 2)
    }

    func freePort() throws -> UInt16 {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        defer { Darwin.close(socket) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(socket, $0, length) == 0 && getsockname(socket, $0, &length) == 0 }
        }
        try #require(bound)
        return UInt16(bigEndian: address.sin_port)
    }

    actor Received {
        var events: [HookEvent] = []
        func add(_ event: HookEvent) { events.append(event) }
    }

    actor Gate {
        var cancelled = 0
        private var waiters: [CheckedContinuation<HookReply, Never>] = []

        func wait() async -> HookReply {
            await withTaskCancellationHandler {
                await withCheckedContinuation { waiters.append($0) }
            } onCancel: {
                Task { await self.cancel() }
            }
        }

        func open(with reply: HookReply) {
            waiters.forEach { $0.resume(returning: reply) }
            waiters.removeAll()
        }

        private func cancel() {
            cancelled += 1
            open(with: .empty)
        }
    }
}
