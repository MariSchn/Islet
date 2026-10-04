import Foundation
import IsletCore
import Testing
@testable import AgentsPlugin

@MainActor
struct AgentSessionStoreTests {
    @Test func storesAndUpdatesTheTmuxLocation() {
        let store = AgentSessionStore()
        let first = TmuxLocation(socket: "/tmp/tmux-501/default", serverPID: 10, pane: "%1")
        let second = TmuxLocation(socket: "/tmp/tmux-501/default", serverPID: 10, pane: "%2")
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "s1", prompt: "go", tmux: first))
        #expect(store.sessions[0].tmux == first)
        store.apply(HookEvent(kind: .stop, sessionID: "s1"))
        #expect(store.sessions[0].tmux == first)
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "s1", prompt: "again", tmux: second))
        #expect(store.sessions[0].tmux == second)
    }

    @Test func antigravityHooksFillTheModelAndBranchUntilTheStatusLineRefinesThem() throws {
        let store = AgentSessionStore()
        var prompt = HookEvent(kind: .userPromptSubmit, sessionID: "c1", prompt: "go", agent: .antigravity)
        prompt.model = "Gemini 3.8 Flash"
        prompt.effort = "high"
        prompt.branch = "main"
        store.apply(prompt)
        #expect(store.sessions[0].details.badgeText == "Gemini 3.8 Flash · high")
        #expect(store.sessions[0].details.branch == "main")

        store.apply(HookEvent(kind: .postToolUse, sessionID: "c1", toolName: "view_file", agent: .antigravity))
        #expect(store.sessions[0].details.branch == "main")
        store.applyStatusLine(try StatusLineUpdate.decode(Data(#"{"session_id":"c1","product":"antigravity","conversation_title":"Fix it","context_window":{"used_percentage":12}}"#.utf8)))
        #expect(store.sessions[0].title == "Fix it")
        #expect(store.sessions[0].details.contextPercentage == 12)
        #expect(store.sessions[0].details.branch == "main")
        #expect(store.sessions[0].details.badgeText == "Gemini 3.8 Flash · high")
    }

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

    @Test func failedTurnsNeedAttentionUntilTheNextPrompt() async {
        let store = AgentSessionStore()
        var alerts: [AgentSessionStore.Alert] = []
        store.onAlert = { alerts.append($0) }
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "s1", cwd: "/tmp/proj", prompt: "go"))
        store.apply(HookEvent(kind: .preToolUse, sessionID: "s1", toolName: "Read", toolInput: .object(["file_path": .string("/a")])))
        store.apply(HookEvent(kind: .stopFailure, sessionID: "s1", error: "rate_limit"))
        #expect(store.sessions[0].state == .failed("Rate limit reached"))
        #expect(store.sessions[0].activity == nil)
        #expect(store.pillStatus(for: DisplaySettings())?.priority == .attention)
        #expect(alerts.count == 1)

        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "s1", prompt: "try again"))
        #expect(store.sessions[0].state == .working)
    }

    @Test func failedToolCallsAndDenialsAreRecorded() async throws {
        let store = AgentSessionStore()
        let command = JSONValue.object(["command": .string("npm test")])
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "s1", prompt: "go"))
        store.apply(HookEvent(kind: .preToolUse, sessionID: "s1", toolName: "Bash", toolInput: command))
        store.apply(HookEvent(kind: .postToolUseFailure, sessionID: "s1", toolName: "Bash", toolInput: command, error: "Exit code 1"))
        #expect(store.sessions[0].activities.count == 1)
        #expect(store.sessions[0].activities[0].isComplete)
        #expect(store.sessions[0].activities[0].didFail)
        #expect(store.sessions[0].state == .working)

        let remove = JSONValue.object(["command": .string("rm -rf /tmp/build")])
        store.apply(HookEvent(kind: .preToolUse, sessionID: "s1", toolName: "Bash", toolInput: remove))
        store.apply(HookEvent(kind: .permissionDenied, sessionID: "s1", toolName: "Bash", toolInput: remove, reason: "[Irreversible Local Destruction]"))
        #expect(store.sessions[0].activity == "Denied: $ rm -rf /tmp/build")
        #expect(store.sessions[0].activities.count == 2)
        #expect(store.sessions[0].activities.last?.didFail == true)
        #expect(store.sessions[0].activities.last?.isComplete == true)

        let reply = Task { await store.handle(HookEvent(kind: .permissionRequest, sessionID: "s1", toolName: "Bash", toolInput: command)) }
        try await waitUntil { store.sessions[0].pendingRequest != nil }
        store.apply(HookEvent(kind: .postToolUseFailure, sessionID: "s1", toolName: "Bash", toolInput: command, error: "Exit code 1"))
        #expect(await reply.value == .empty)
        #expect(store.sessions[0].pendingRequest == nil)
    }

    @Test func unknownEventsAreIgnored() async {
        let store = AgentSessionStore()
        #expect(await store.handle(HookEvent(kind: .other, sessionID: "s1")) == .empty)
        #expect(store.sessions.isEmpty)
    }

    @Test func theStatusLineRenamesSessions() {
        let store = AgentSessionStore()
        store.apply(HookEvent(kind: .sessionStart, sessionID: "hidden", cwd: "/p/a"))
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "shown", cwd: "/p/b", prompt: "go", title: "old"))

        store.applyStatusLine(StatusLineUpdate(sessionID: "shown", sessionName: "renamed"))
        store.applyStatusLine(StatusLineUpdate(sessionID: "hidden", sessionName: "named early"))
        store.applyStatusLine(StatusLineUpdate(sessionID: "unknown", sessionName: "ignored"))
        store.applyStatusLine(StatusLineUpdate(sessionID: "shown", sessionName: nil))
        #expect(store.sessions.map(\.displayName) == ["renamed"])

        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "hidden", prompt: "go"))
        #expect(store.sessions.first { $0.id == "hidden" }?.displayName == "named early")

        store.apply(HookEvent(kind: .stop, sessionID: "shown", title: "from transcript"))
        #expect(store.sessions.first { $0.id == "shown" }?.displayName == "renamed")
    }

    @Test func statusLineDetailsKeepPreviousValuesWhenFieldsAreMissing() throws {
        let store = AgentSessionStore()
        store.apply(HookEvent(kind: .sessionStart, sessionID: "hidden", cwd: "/tmp/hidden"))
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "shown", cwd: "/tmp/shown", prompt: "go"))
        let full = SessionDetails(contextPercentage: 40, model: "Opus 4.7", effort: "high", fastMode: true)
        store.applyStatusLine(StatusLineUpdate(sessionID: "shown", sessionName: "named", details: full))
        store.applyStatusLine(StatusLineUpdate(sessionID: "hidden", sessionName: "early", details: full))
        store.applyStatusLine(StatusLineUpdate(sessionID: "shown", sessionName: nil))
        #expect(store.sessions[0].details == full)
        #expect(store.sessions[0].displayName == "named")

        let cleared = try StatusLineUpdate.decode(Data(#"{"session_id":"shown","context_window":{"used_percentage":null},"model":{"display_name":""}}"#.utf8))
        store.applyStatusLine(cleared)
        #expect(store.sessions[0].details == full)

        store.applyStatusLine(StatusLineUpdate(sessionID: "shown", details: SessionDetails(contextPercentage: 12, model: "Sonnet", fastMode: false)))
        #expect(store.sessions[0].details == SessionDetails(contextPercentage: 12, model: "Sonnet", effort: "high", fastMode: false))

        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "hidden", prompt: "go"))
        #expect(store.sessions.first { $0.id == "hidden" }?.details == full)
        #expect(store.sessions.first { $0.id == "hidden" }?.displayName == "early")
    }

    @Test func aMissingPullRequestClearsThePreviousOne() throws {
        let store = AgentSessionStore()
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "s", cwd: "/tmp/proj", prompt: "go"))
        let open = try StatusLineUpdate.decode(Data(#"{"session_id":"s","model":{"display_name":"Opus"},"worktree":{"name":"my-feature"},"pr":{"number":42,"url":"https://example.com/42","review_state":"pending"}}"#.utf8))
        store.applyStatusLine(open)
        #expect(store.sessions[0].details.worktree == "my-feature")
        #expect(store.sessions[0].details.pullRequest?.number == 42)
        #expect(store.sessions[0].details.model == "Opus")

        let closed = try StatusLineUpdate.decode(Data(#"{"session_id":"s"}"#.utf8))
        store.applyStatusLine(closed)
        #expect(store.sessions[0].details.worktree == nil)
        #expect(store.sessions[0].details.pullRequest == nil)
        #expect(store.sessions[0].details.model == "Opus")
    }

    @Test func walksThroughSessionLifecycle() {
        let store = AgentSessionStore()
        store.apply(HookEvent(kind: .sessionStart, sessionID: "s1", cwd: "/tmp/proj"))
        #expect(store.sessions.isEmpty)
        #expect(store.pillStatus(for: DisplaySettings()) == nil)

        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "s1", prompt: "fix the auth bug\nmore details"))
        #expect(store.sessions.count == 1)
        #expect(store.sessions[0].projectName == "proj")
        #expect(store.sessions[0].task == "fix the auth bug")
        #expect(store.sessions[0].state == .working)
        #expect(store.pillStatus(for: DisplaySettings())?.text == "proj")

        store.apply(HookEvent(kind: .preToolUse, sessionID: "s1", toolName: "Read", toolInput: .object(["file_path": .string("/a/b.swift")])))
        #expect(store.sessions[0].activity == "Read b.swift")
        #expect(store.pillStatus(for: DisplaySettings())?.text == "Read b.swift")

        store.apply(HookEvent(kind: .notification, sessionID: "s1", message: "Claude needs your permission to use Bash", notificationType: "permission_prompt"))
        #expect(store.sessions[0].state == .needsAttention("Claude needs your permission to use Bash"))
        #expect(store.pillStatus(for: DisplaySettings())?.priority == .attention)
        #expect(store.pillStatus(for: DisplaySettings())?.text == "proj needs you")

        store.apply(HookEvent(kind: .postToolUse, sessionID: "s1", toolName: "Bash"))
        #expect(store.sessions[0].state == .working)

        store.apply(HookEvent(kind: .stop, sessionID: "s1"))
        #expect(store.sessions[0].state == .done)
        #expect(store.pillStatus(for: DisplaySettings())?.text == "proj finished")

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
        #expect(store.pillStatus(for: DisplaySettings())?.text == "one finished")

        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "b", cwd: "/two", prompt: "y"))
        #expect(store.pillStatus(for: DisplaySettings())?.text == "two")
        store.apply(HookEvent(kind: .sessionEnd, sessionID: "b"))
        #expect(store.pillStatus(for: DisplaySettings())?.text == "one finished")

        clock = clock.addingTimeInterval(AgentSessionStore.finishedPillDuration + 1)
        #expect(store.pillStatus(for: DisplaySettings()) == nil)
        #expect(store.sessions.count == 1)
    }

    @Test func remoteSessionsShowTheirHostAndGoUnreachableWithoutUpdates() {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let store = AgentSessionStore(now: { clock }, localHost: { "MacBook" })
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "local", cwd: "/one", prompt: "x", host: "macbook"))
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "remote", cwd: "/two", prompt: "y", host: "devbox"))
        #expect(store.sessions.map(\.isRemote) == [true, false])
        #expect(store.pillStatus(for: DisplaySettings())?.text == "2 agents working")

        clock = clock.addingTimeInterval(AgentSessionStore.unreachableTimeout + 1)
        store.markUnreachableSessions()
        #expect(store.sessions.map(\.isUnreachable) == [true, false])
        #expect(store.pillStatus(for: DisplaySettings())?.text == "one")

        store.apply(HookEvent(kind: .preToolUse, sessionID: "remote", toolName: "Read"))
        #expect(store.sessions[0].isUnreachable == false)
        store.apply(HookEvent(kind: .stop, sessionID: "remote"))
        clock = clock.addingTimeInterval(AgentSessionStore.unreachableTimeout + 1)
        store.markUnreachableSessions()
        #expect(store.sessions[0].isUnreachable == false)
    }

    @Test func sessionsStayHiddenUntilTheirFirstActivity() {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let started = clock
        let store = AgentSessionStore(now: { clock })
        store.apply(HookEvent(kind: .sessionStart, sessionID: "s", cwd: "/p/proj", title: "Spare"))
        store.apply(HookEvent(kind: .notification, sessionID: "s", notificationType: "idle_prompt"))
        store.apply(HookEvent(kind: .notification, sessionID: "s", message: "Authentication successful", notificationType: "auth_success"))
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "s", prompt: "<task-notification>done</task-notification>"))
        #expect(store.sessions.isEmpty)
        #expect(store.pillStatus(for: DisplaySettings()) == nil)

        clock = clock.addingTimeInterval(30)
        store.apply(HookEvent(kind: .preToolUse, sessionID: "s", toolName: "Read"))
        #expect(store.sessions.map(\.id) == ["s"])
        #expect(store.sessions[0].startedAt == started)
        #expect(store.sessions[0].displayName == "Spare")
        #expect(store.sessions[0].projectName == "proj")

        store.apply(HookEvent(kind: .sessionStart, sessionID: "ended", cwd: "/p"))
        store.apply(HookEvent(kind: .sessionEnd, sessionID: "ended"))
        store.apply(HookEvent(kind: .notification, sessionID: "ended", message: "Pick one", notificationType: "elicitation_dialog"))
        #expect(store.sessions.first { $0.id == "ended" }?.cwd == nil)
    }

    @Test func hiddenSessionsOfExitedProcessesAreForgotten() {
        let store = AgentSessionStore(localHost: { "mac" })
        store.apply(HookEvent(kind: .sessionStart, sessionID: "spare", cwd: "/p/spare", host: "mac", pid: 90))
        store.removeExitedSessions { _ in false }
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "spare", prompt: "late", host: "mac"))
        #expect(store.sessions.first?.cwd == nil)
    }

    @Test func aClaudeProcessOnlyKeepsItsLatestSession() {
        let store = AgentSessionStore(localHost: { "mac" })
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "startup", cwd: "/p", prompt: "a", host: "mac", pid: 42))
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "other-host", cwd: "/p", prompt: "b", host: "devbox", pid: 42))
        store.apply(HookEvent(kind: .sessionStart, sessionID: "resumed", cwd: "/p", host: "mac", pid: 42))
        #expect(store.sessions.map(\.id) == ["other-host"])

        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "resumed", prompt: "go", host: "mac", pid: 42))
        store.apply(HookEvent(kind: .preToolUse, sessionID: "resumed", toolName: "WebSearch", host: "mac", pid: 42))
        #expect(store.sessions.map(\.id) == ["resumed", "other-host"])
        store.apply(HookEvent(kind: .sessionStart, sessionID: "after-backgrounding", cwd: "/p", host: "mac", pid: 42))
        #expect(store.sessions.map(\.id) == ["other-host"])

        store.apply(HookEvent(kind: .sessionStart, sessionID: "fork-spare", cwd: "/p", host: "mac", pid: 50))
        store.apply(HookEvent(kind: .sessionStart, sessionID: "fork", cwd: "/p", source: "fork", host: "mac", pid: 50))
        store.apply(HookEvent(kind: .sessionStart, sessionID: "late-spare", cwd: "/p", host: "mac", pid: 50))
        store.apply(HookEvent(kind: .preToolUse, sessionID: "fork", toolName: "Read", host: "mac", pid: 50))
        #expect(store.sessions.map(\.id) == ["fork", "other-host"])
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "late-spare", prompt: "revived", host: "mac", pid: 51))
        #expect(store.sessions.first { $0.id == "late-spare" }?.cwd == nil)

        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "busy", prompt: "x", host: "mac", pid: 60))
        store.apply(HookEvent(kind: .preToolUse, sessionID: "sibling", toolName: "Read", host: "mac", pid: 60))
        #expect(store.sessions.contains { $0.id == "busy" })

        store.apply(HookEvent(kind: .sessionStart, sessionID: "codex-a", cwd: "/p", agent: .codex, host: "mac", pid: 70))
        store.apply(HookEvent(kind: .sessionStart, sessionID: "codex-b", cwd: "/p", agent: .codex, host: "mac", pid: 70))
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "codex-a", prompt: "x", agent: .codex, host: "mac", pid: 70))
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "codex-b", prompt: "y", agent: .codex, host: "mac", pid: 70))
        #expect(store.sessions.contains { $0.id == "codex-a" } && store.sessions.contains { $0.id == "codex-b" })
    }

    @Test func forkedAndResumedSessionsShowTheirLastPrompt() async throws {
        let store = AgentSessionStore(localHost: { "mac" }, lastPrompt: { $0 == "/t/bg.jsonl" ? "Research something on the web\nand ask me" : "unexpected read" })
        store.apply(HookEvent(kind: .sessionStart, sessionID: "bg", cwd: "/p", transcriptPath: "/t/bg.jsonl", source: "fork", host: "mac", pid: 7))
        store.apply(HookEvent(kind: .preToolUse, sessionID: "bg", toolName: "Read", host: "mac", pid: 7))
        try await waitUntil { store.sessions.first { $0.id == "bg" }?.task != nil }
        #expect(store.sessions.first { $0.id == "bg" }?.task == "Research something on the web")

        store.apply(HookEvent(kind: .sessionStart, sessionID: "hidden-bg", cwd: "/p", transcriptPath: "/t/bg.jsonl", source: "fork", host: "mac", pid: 11))
        try await Task.sleep(for: .milliseconds(100))
        store.apply(HookEvent(kind: .preToolUse, sessionID: "hidden-bg", toolName: "Read", host: "mac", pid: 11))
        #expect(store.sessions.first { $0.id == "hidden-bg" }?.task == "Research something on the web")

        store.apply(HookEvent(kind: .sessionStart, sessionID: "fresh", cwd: "/p", transcriptPath: "/t/fresh.jsonl", source: "startup", host: "mac", pid: 8))
        store.apply(HookEvent(kind: .sessionStart, sessionID: "remote", cwd: "/p", transcriptPath: "/t/remote.jsonl", source: "resume", host: "devbox", pid: 9))
        store.apply(HookEvent(kind: .sessionStart, sessionID: "prompted", cwd: "/p", transcriptPath: "/t/prompted.jsonl", source: "resume", host: "mac", pid: 10))
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "prompted", prompt: "newer prompt", host: "mac", pid: 10))
        try await Task.sleep(for: .milliseconds(100))
        store.apply(HookEvent(kind: .preToolUse, sessionID: "fresh", toolName: "Read", host: "mac", pid: 8))
        store.apply(HookEvent(kind: .preToolUse, sessionID: "remote", toolName: "Read", host: "devbox", pid: 9))
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
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "interrupted", prompt: "d"))
        store.markInterrupted("interrupted")
        #expect(store.pillStatus(for: DisplaySettings())?.ring?.segments == [
            .init(value: 1, tint: SessionColors.workingTint),
            .init(value: 2, tint: SessionColors.finishedTint),
            .init(value: 1, tint: SessionColors.idleTint),
        ])

        store.apply(HookEvent(kind: .notification, sessionID: "working", message: "Pick one", notificationType: "elicitation_dialog"))
        #expect(store.pillStatus(for: DisplaySettings())?.priority == .attention)
        #expect(store.pillStatus(for: DisplaySettings())?.ring?.segments.first == .init(value: 1, tint: SessionColors.attentionTint))
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

    @Test func thePillFollowsTheDisplaySettings() {
        let store = AgentSessionStore()
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "a", cwd: "/p/alpha", prompt: "go"))
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "b", cwd: "/p/beta", prompt: "go"))
        store.apply(HookEvent(kind: .stop, sessionID: "b"))
        var display = DisplaySettings()
        #expect(store.pillStatus(for: display)?.ring != nil)

        display.pillContent = .summary
        #expect(store.pillStatus(for: display)?.ring == nil)
        #expect(store.pillStatus(for: display)?.text == "alpha")

        display.pillShowsWorking = false
        #expect(store.pillStatus(for: display)?.text == "beta finished")

        display.pillShowsFinished = false
        #expect(store.pillStatus(for: display) == nil)

        store.apply(HookEvent(kind: .notification, sessionID: "a", message: "Pick one", notificationType: "elicitation_dialog"))
        #expect(store.pillStatus(for: display)?.text == "alpha needs you")
        #expect(store.pillStatus(for: display)?.priority == .attention)
    }

    @Test func oldFinishedSessionsStayFinishedInTheRingUnlessTheyShouldTurnIdle() {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let store = AgentSessionStore(now: { clock })
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "old", prompt: "a"))
        store.apply(HookEvent(kind: .stop, sessionID: "old"))
        clock = clock.addingTimeInterval(AgentSessionStore.finishedPillDuration + 1)
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "new", prompt: "b"))
        #expect(store.statusRing(keepingFinishedSessions: true).segments == [
            .init(value: 1, tint: SessionColors.workingTint),
            .init(value: 1, tint: SessionColors.finishedTint),
        ])
        #expect(store.statusRing(keepingFinishedSessions: false).segments == [
            .init(value: 1, tint: SessionColors.workingTint),
            .init(value: 1, tint: SessionColors.idleTint),
        ])

        var display = DisplaySettings()
        display.ringKeepsFinishedSessions = false
        #expect(store.pillStatus(for: display)?.ring == store.statusRing(keepingFinishedSessions: false))
    }

    @Test func thePillNamesSessionsByTitleWhenTheyHaveOne() {
        let store = AgentSessionStore()
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "a", cwd: "/p/proj", prompt: "hi"))
        store.apply(HookEvent(kind: .stop, sessionID: "a", cwd: "/p/proj"))
        #expect(store.pillStatus(for: DisplaySettings())?.text == "proj finished")
        store.apply(HookEvent(kind: .stop, sessionID: "a", cwd: "/p/proj", title: "islet-main"))
        #expect(store.pillStatus(for: DisplaySettings())?.text == "islet-main finished")
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
        #expect(store.pillStatus(for: DisplaySettings())?.text == "2 agents working")

        store.apply(HookEvent(kind: .notification, sessionID: "a", message: "Claude needs your permission", notificationType: "permission_prompt"))
        store.apply(HookEvent(kind: .permissionRequest, sessionID: "b", toolName: "Bash", toolInput: .object(["command": .string("rm -rf build")])))
        #expect(store.sessions.first { $0.id == "b" }?.state == .needsAttention("Wants to $ rm -rf build"))
        #expect(store.pillStatus(for: DisplaySettings())?.text == "2 agents need you")

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
        #expect(store.pillStatus(for: DisplaySettings())?.text == "one needs you")

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

    @Test func alwaysAllowReturnsTheSuggestedRule() async throws {
        let store = AgentSessionStore()
        let suggestion: JSONValue = .object([
            "type": .string("addRules"),
            "rules": .array([.object(["toolName": .string("Bash"), "ruleContent": .string("ls -la /tmp")])]),
            "behavior": .string("allow"),
            "destination": .string("localSettings"),
        ])
        let event = HookEvent(
            kind: .permissionRequest,
            sessionID: "a",
            cwd: "/x/one",
            toolName: "Bash",
            toolInput: .object(["command": .string("ls -la /tmp")]),
            permissionSuggestions: [suggestion]
        )
        async let reply = store.handle(event)
        try await waitForPendingRequest(in: store)
        let request = try #require(store.sessions.first?.pendingRequest)
        #expect(request.alwaysAllowRule == suggestion)
        store.decide(request.id, .allowAlways)
        #expect(await reply.body.contains(#""updatedPermissions""#))
        #expect(store.sessions.first?.pendingRequest == nil)
        #expect(store.sessions.first?.state == .working)
        #expect(store.sessions.first?.activity == nil)
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
        #expect(store.pillStatus(for: DisplaySettings()) == nil)
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
}
