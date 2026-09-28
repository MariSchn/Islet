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

    @Test func decodesUnknownEventsAsOther() throws {
        #expect(try HookEvent.decode(Data(#"{"session_id":"a","hook_event_name":"Nope"}"#.utf8)).kind == .other)
    }

    @Test func takesTheSessionTitleFromThePayloadUnlessTheScriptFoundOne() throws {
        let payload = Data(#"{"session_id":"a","hook_event_name":"SessionStart","session_title":"from payload"}"#.utf8)
        #expect(try HookEvent.decode(payload).title == "from payload")
        #expect(try HookEvent.decode(payload, title: "from transcript").title == "from transcript")
        #expect(try HookEvent.decode(Data(#"{"session_id":"a","hook_event_name":"SessionStart","session_title":""}"#.utf8)).title == nil)
    }

    @Test func describesFailedTurns() throws {
        let rateLimit = try HookEvent.decode(Data(#"{"session_id":"a","hook_event_name":"StopFailure","error":"rate_limit","last_assistant_message":"API Error: Rate limit reached"}"#.utf8))
        #expect(rateLimit.kind == .stopFailure)
        #expect(rateLimit.failureDescription == "Rate limit reached")
        #expect(HookEvent(kind: .stopFailure, sessionID: "a", error: "unknown", lastAssistantMessage: "API Error: boom").failureDescription == "API Error: boom")
        #expect(HookEvent(kind: .stopFailure, sessionID: "a").failureDescription == "The request failed")
    }
}
