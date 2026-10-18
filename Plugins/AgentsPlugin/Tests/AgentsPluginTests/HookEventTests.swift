import Foundation
import IsletCore
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

    @Test func decodesTheBackgroundTaskFromTheToolResponse() throws {
        let bash = try HookEvent.decode(Data(#"{"session_id":"a","hook_event_name":"PostToolUse","tool_name":"Bash","tool_use_id":"toolu_1","tool_input":{"command":"gh run watch"},"tool_response":{"stdout":"","interrupted":false,"backgroundTaskId":"bt7358twk"}}"#.utf8))
        #expect(bash.toolUseID == "toolu_1")
        #expect(BackgroundTask(launchedBy: bash) == BackgroundTask(id: "bt7358twk", toolUseID: "toolu_1", label: "Waiting: $ gh run watch"))
        let agent = try HookEvent.decode(Data(#"{"session_id":"a","hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"description":"Review"},"tool_response":{"isAsync":true,"status":"async_launched","agentId":"acf27962a7dd3baa7"}}"#.utf8))
        #expect(BackgroundTask(launchedBy: agent)?.id == "acf27962a7dd3baa7")
        let read = try HookEvent.decode(Data(#"{"session_id":"a","hook_event_name":"PostToolUse","tool_name":"Read","tool_response":"file contents"}"#.utf8))
        #expect(read.toolResponse == nil)
        #expect(BackgroundTask(launchedBy: read) == nil)
    }

    @Test func mapsAntigravityHooksOntoSessionEvents() throws {
        let common = #""conversationId":"c1","workspacePaths":["/Users/me/projects/islet"],"transcriptPath":"/tmp/t.jsonl","modelName":"gemini-3.8-flash-high""#
        func decode(_ name: String, _ fields: String = "") throws -> HookEvent {
            try HookEvent.decode(Data("{\(common)\(fields)}".utf8), agent: "antigravity", eventName: name, lastPrompt: { $0 == "/tmp/t.jsonl" ? "Fix the build" : nil }, parent: { _ in nil })
        }

        let prompt = try decode("PreInvocation", #","invocationNum":0,"initialNumSteps":1"#)
        #expect(prompt.kind == .userPromptSubmit)
        #expect(prompt.agent == .antigravity)
        #expect(prompt.sessionID == "c1")
        #expect(prompt.cwd == "/Users/me/projects/islet")
        #expect(prompt.prompt == "Fix the build")
        #expect(try decode("PreInvocation", #","invocationNum":2"#).kind == .other)
        #expect(try decode("PostInvocation", #","invocationNum":0"#).kind == .other)

        let tool = try decode("PostToolUse", #","error":"","toolCall":{"name":"view_file","args":{"AbsolutePath":"/a.txt","toolSummary":"Read a.txt"}}"#)
        #expect(tool.kind == .postToolUse)
        #expect(tool.toolName == "view_file")
        #expect(tool.activityDescription == "Read a.txt")
        #expect(try decode("PostToolUse", #","error":"exit status 1","toolCall":{"name":"run_command"}"#).kind == .postToolUseFailure)

        #expect(try decode("Stop", #","error":"","terminationReason":"NO_TOOL_CALL""#).kind == .stop)
        let failure = try decode("Stop", #","error":"quota exceeded","terminationReason":"error""#)
        #expect(failure.kind == .stopFailure)
        #expect(failure.failureDescription == "quota exceeded")
        #expect(throws: (any Error).self) { try HookEvent.decode(Data(#"{"session_id":"a","hook_event_name":"Stop"}"#.utf8), agent: "antigravity", eventName: "Stop") }
    }

    @Test func mapsCursorHooksOntoSessionEvents() throws {
        let common = #""conversation_id":"c1","generation_id":"g1","model":"claude-4.5-sonnet","cursor_version":"3.23.23","workspace_roots":["/Users/me/projects/islet"],"transcript_path":"/tmp/t.jsonl""#
        func decode(_ name: String, _ fields: String = "") throws -> HookEvent {
            try HookEvent.decode(Data("{\(common)\(fields)}".utf8), agent: "cursor", eventName: name)
        }

        let prompt = try decode("UserPromptSubmit", #","hook_event_name":"beforeSubmitPrompt","composer_mode":"agent","prompt":"Fix the build","attachments":[],"model":"claude-opus-5-5-medium","model_id":"claude-opus-5-5","model_params":[{"id":"context","value":"300k"},{"id":"effort","value":"medium"}]"#)
        #expect(prompt.kind == .userPromptSubmit)
        #expect(prompt.agent == .cursor)
        #expect(prompt.sessionID == "c1")
        #expect(prompt.cwd == "/Users/me/projects/islet")
        #expect(prompt.prompt == "Fix the build")
        #expect(prompt.model == "claude-opus-5-5")
        #expect(prompt.effort == "medium")

        #expect(try decode("UserPromptSubmit", #","prompt":"rename this var""#).kind == .other)

        let tool = try decode("PreToolUse", #","hook_event_name":"preToolUse","tool_name":"Shell","tool_input":{"command":"swift test"},"tool_use_id":"t1""#)
        #expect(tool.kind == .preToolUse)
        #expect(tool.activityDescription == "$ swift test")
        #expect(tool.model == "claude-4.5-sonnet")
        #expect(tool.effort == nil)
        #expect(try decode("PostToolUseFailure", #","tool_name":"Shell","error_message":"exit 1","failure_type":"error""#).kind == .postToolUseFailure)

        #expect(try decode("Stop", #","status":"completed","loop_count":0"#).kind == .stop)
        #expect(try !decode("Stop", #","status":"completed","loop_count":0"#).isInterruption)
        let aborted = try decode("Stop", #","status":"aborted","loop_count":0"#)
        #expect(aborted.kind == .stop)
        #expect(aborted.isInterruption)
        #expect(try HookEvent.decode(Data(#"{"conversation_id":"c1","model":"unknown"}"#.utf8), agent: "cursor", eventName: "Stop").model == nil)
        let failure = try decode("Stop", #","status":"error","loop_count":0"#)
        #expect(failure.kind == .stopFailure)
        #expect(failure.failureDescription == "The request failed")
        #expect(try decode("SessionEnd", #","session_id":"c1","reason":"user_close""#).kind == .sessionEnd)
        #expect(try decode("afterAgentThought").kind == .other)
        #expect(throws: (any Error).self) { try HookEvent.decode(Data(#"{"session_id":"a"}"#.utf8), agent: "cursor", eventName: "Stop") }
    }

    @Test func antigravitySubagentToolCallsShowOnTheParentAndNothingElse() throws {
        let fields = #""conversationId":"sub1","transcriptPath":"/tmp/sub.jsonl","error":"","invocationNum":0,"toolCall":{"name":"view_file","args":{"toolSummary":"Read a.txt"}}"#
        func decode(_ name: String) throws -> HookEvent {
            try HookEvent.decode(Data("{\(fields)}".utf8), agent: "antigravity", eventName: name, lastPrompt: { _ in "delegated task" }, parent: { $0 == "/tmp/sub.jsonl" ? "c1" : nil })
        }
        let tool = try decode("PostToolUse")
        #expect(tool.kind == .postToolUse)
        #expect(tool.sessionID == "c1")
        #expect(tool.activityDescription == "Subagent: Read a.txt")
        #expect(try decode("PreInvocation").kind == .other)
        #expect(try decode("Stop").kind == .other)

        let subagent = #"{"step_index":0,"source":"SYSTEM","type":"SYSTEM_MESSAGE","content":"<SYSTEM_MESSAGE>\n[Message] timestamp=2026-10-04T10:24:42Z sender=1d3e15ab-9d79-4fa7-9489-e3fd35aca1d8 priority=MESSAGE_PRIORITY_HIGH content=Read a.txt"}"#
        #expect(TranscriptReader.antigravityParent(in: Data(subagent.utf8)) == "1d3e15ab-9d79-4fa7-9489-e3fd35aca1d8")
        #expect(TranscriptReader.antigravityParent(in: Data(#"{"type":"USER_INPUT","source":"USER_EXPLICIT","content":"sender=x"}"#.utf8)) == nil)
    }

    @Test func cursorSubagentToolCallsShowOnTheParentAndNothingElse() throws {
        let fields = #""conversation_id":"sub1","generation_id":"","model":"cursor-grok-4.5-high","parent_tool_call_id":"toolu_1","tool_name":"Read","tool_input":{"file_path":"/tmp/a.txt"}"#
        func decode(_ name: String, parent: String? = "c1") throws -> HookEvent {
            try HookEvent.decode(Data("{\(fields)}".utf8), agent: "cursor", eventName: name, title: "Subagent chat", cursorParent: { $0 == "toolu_1" ? parent : nil })
        }
        let tool = try decode("PreToolUse")
        #expect(tool.kind == .preToolUse)
        #expect(tool.sessionID == "c1")
        #expect(tool.agentID == "sub1")
        #expect(tool.model == nil)
        #expect(tool.title == nil)
        #expect(tool.activityDescription == "Subagent: Read a.txt")
        #expect(try decode("PostToolUse").kind == .postToolUse)
        #expect(try decode("PostToolUseFailure").kind == .postToolUseFailure)
        #expect(try decode("UserPromptSubmit").kind == .other)
        #expect(try decode("Stop").kind == .other)
        #expect(try decode("PreToolUse", parent: nil).kind == .other)
    }

    @Test func readsTheUserRequestFromAnAntigravityTranscript() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "AgentsPluginTests." + UUID().uuidString + ".jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        {"step_index":0,"type":"USER_INPUT","content":"<USER_REQUEST>\\nFirst task\\n</USER_REQUEST>"}
        {"step_index":1,"type":"PLANNER_RESPONSE","content":"<USER_REQUEST>ignored</USER_REQUEST>"}
        {"step_index":2,"type":"USER_INPUT","content":"<USER_REQUEST>\\nSay \\"hi\\"\\nplease\\n</USER_REQUEST>\\n<ADDITIONAL_METADATA>\\ntime\\n</ADDITIONAL_METADATA>"}
        {"step_index":3,"type":"PLANNER_RESPONSE","content":"ok"}

        """.write(to: url, atomically: true, encoding: .utf8)
        #expect(TranscriptReader.lastAntigravityPrompt(at: url.path) == "Say \"hi\"\nplease")
        #expect(TranscriptReader.lastAntigravityPrompt(at: url.path + ".missing") == nil)
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
        #expect(ActivityEntry.detail(for: "Read", input: .object(["offset": .number(1e300), "limit": .number(20)])) == nil)
        #expect(ActivityEntry.detail(for: "Read", input: .object(["offset": .number(10), "limit": .number(-1e300)])) == "from line 10")
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

    @Test func decodesTheModelAndRecognizesGeminiSessions() throws {
        let event = try HookEvent.decode(Data(#"{"session_id":"a","hook_event_name":"SessionStart","model":"gemini-3-pro"}"#.utf8), agent: "codex")
        #expect(event.model == "gemini-3-pro")
        var session = AgentSession(id: "a", agent: .codex, state: .starting, startedAt: .now, turnStartedAt: .now, updatedAt: .now)
        #expect(!session.isGeminiModel)
        session.details.model = "Gemini 3 Pro"
        #expect(session.isGeminiModel)
    }

    @Test func takesTheClaudeModelAndEffortFromTheHeadersUnlessThePayloadHasAModel() throws {
        let stop = Data(#"{"session_id":"a","hook_event_name":"Stop"}"#.utf8)
        let event = try HookEvent.decode(stop, model: "claude-opus-5-5", effort: "high")
        #expect(event.model == "Opus 5.5")
        #expect(event.effort == "high")
        #expect(try HookEvent.decode(stop, model: "", effort: "bogus").model == nil)
        #expect(try HookEvent.decode(stop, model: "", effort: "bogus").effort == nil)
        let start = Data(#"{"session_id":"a","hook_event_name":"SessionStart","model":"claude-sonnet-5-5"}"#.utf8)
        #expect(try HookEvent.decode(start, model: "claude-opus-5-5").model == "Sonnet 5.5")
        #expect(try HookEvent.decode(start, model: "claude-opus-5-5", effort: "xhigh").effort == nil)
        #expect(try HookEvent.decode(start, agent: "codex", model: "claude-opus-5-5").model == "claude-sonnet-5-5")
    }

    @Test func takesTheBranchFromTheHeader() throws {
        let data = Data(#"{"session_id":"a","hook_event_name":"Stop"}"#.utf8)
        #expect(try HookEvent.decode(data, branch: "main").branch == "main")
        #expect(try HookEvent.decode(data, branch: "").branch == nil)
    }

    @Test func decodesUnknownEventsAsOther() throws {
        #expect(try HookEvent.decode(Data(#"{"session_id":"a","hook_event_name":"Nope"}"#.utf8)).kind == .other)
    }

    @Test func takesTheSessionTitleFromThePayloadUnlessTheScriptFoundOne() throws {
        let payload = Data(#"{"session_id":"a","hook_event_name":"SessionStart","session_title":"from payload"}"#.utf8)
        #expect(try HookEvent.decode(payload).title == "from payload")
        #expect(try HookEvent.decode(payload, title: "from transcript").title == "from transcript")
        #expect(try HookEvent.decode(Data(#"{"session_id":"a","hook_event_name":"SessionStart","session_title":""}"#.utf8)).title == nil)
    }

    @Test func decodesPermissionSuggestionsAndIgnoresMalformedOnes() throws {
        let json = """
        {"session_id":"abc","hook_event_name":"PermissionRequest","tool_name":"Bash","permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"rm -rf node_modules"}],"behavior":"allow","destination":"localSettings"}]}
        """
        let event = try HookEvent.decode(Data(json.utf8))
        let suggestion = try #require(event.permissionSuggestions?.first)
        #expect(suggestion["type"]?.stringValue == "addRules")
        #expect(suggestion["behavior"]?.stringValue == "allow")
        #expect(suggestion["destination"]?.stringValue == "localSettings")
        #expect(suggestion["rules"]?.arrayValue?.first?["toolName"]?.stringValue == "Bash")
        #expect(suggestion["rules"]?.arrayValue?.first?["ruleContent"]?.stringValue == "rm -rf node_modules")

        let malformed = Data(#"{"session_id":"abc","hook_event_name":"PermissionRequest","permission_suggestions":"nope"}"#.utf8)
        #expect(try HookEvent.decode(malformed).permissionSuggestions == nil)
    }

    @Test func describesFailedTurns() throws {
        let rateLimit = try HookEvent.decode(Data(#"{"session_id":"a","hook_event_name":"StopFailure","error":"rate_limit","last_assistant_message":"API Error: Rate limit reached"}"#.utf8))
        #expect(rateLimit.kind == .stopFailure)
        #expect(rateLimit.failureDescription == "Rate limit reached")
        #expect(HookEvent(kind: .stopFailure, sessionID: "a", error: "unknown", lastAssistantMessage: "API Error: boom").failureDescription == "API Error: boom")
        #expect(HookEvent(kind: .stopFailure, sessionID: "a").failureDescription == "The request failed")
    }

    @Test func decodesTmuxLocationAndDropsInvalidOnes() throws {
        let payload = Data(#"{"session_id":"a","hook_event_name":"Stop"}"#.utf8)
        let valid = try HookEvent.decode(payload, tmux: "/private/tmp/tmux-501/default,1234,0", tmuxPane: "%3")
        #expect(valid.tmux == TmuxLocation(socket: "/private/tmp/tmux-501/default", serverPID: 1234, pane: "%3"))
        #expect(try HookEvent.decode(payload, tmux: "", tmuxPane: "").tmux == nil)
        #expect(try HookEvent.decode(payload, tmux: "tmux/default,1234,0", tmuxPane: "%3").tmux == nil)
        #expect(try HookEvent.decode(payload, tmux: "/tmp/tmux-501/default,1234,0", tmuxPane: "3").tmux == nil)
        #expect(try HookEvent.decode(payload, tmux: "/tmp/tmux-501/default,1234,0", tmuxPane: "%3a").tmux == nil)
        #expect(try HookEvent.decode(payload, tmux: "/tmp/x;id,1234,0", tmuxPane: "%3").tmux == nil)
        #expect(try HookEvent.decode(payload, tmux: "/tmp/tmux-501/default,abc,0", tmuxPane: "%3").tmux == nil)
    }
}
