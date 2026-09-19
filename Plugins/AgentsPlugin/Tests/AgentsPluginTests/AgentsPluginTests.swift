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
    }

    @Test func rejectsUnknownEvents() {
        #expect(throws: (any Error).self) {
            try HookEvent.decode(Data(#"{"session_id":"a","hook_event_name":"Nope"}"#.utf8))
        }
    }
}

@MainActor
struct AgentSessionStoreTests {
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
struct AgentsPluginSizingTests {
    @Test func contentGrowsWithSessionsUpToAScrollingMaximum() {
        #expect(AgentsPlugin.contentSize(forSessionCount: 0) == CGSize(width: 520, height: 130))
        #expect(AgentsPlugin.contentSize(forSessionCount: 1) == CGSize(width: 520, height: 78))
        #expect(AgentsPlugin.contentSize(forSessionCount: 2) == CGSize(width: 520, height: 136))
        #expect(AgentsPlugin.contentSize(forSessionCount: 4) == AgentsPlugin.contentSize(forSessionCount: 9))
    }
}

struct HookInstallerTests {
    func makeInstaller() throws -> HookInstaller {
        let directory = FileManager.default.temporaryDirectory.appending(path: "AgentsPluginTests." + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return HookInstaller(claudeDirectory: directory, port: 7365, token: "deadbeef")
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
        #expect(Set(hooks.keys) == Set(HookInstaller.events))
        let preToolUse = hooks["PreToolUse"] as! [[String: Any]]
        #expect(preToolUse.count == 2)
        #expect((preToolUse[0]["matcher"] as? String) == "Bash")

        let script = try String(contentsOf: installer.scriptURL, encoding: .utf8)
        #expect(script.contains("Bearer deadbeef"))
        #expect(script.contains("127.0.0.1:7365/hook"))
        let permissions = try FileManager.default.attributesOfItem(atPath: installer.scriptURL.path)[.posixPermissions] as! Int
        #expect(permissions == 0o700)
        #expect(try String(contentsOf: installer.settingsURL, encoding: .utf8).contains("\"command\" : \"/"))

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

    @Test func outdatedScriptCountsAsNotInstalled() throws {
        let installer = try makeInstaller()
        try installer.install()
        try "#!/bin/sh\nexit 0\n".write(to: installer.scriptURL, atomically: true, encoding: .utf8)
        #expect(!installer.isInstalled)
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

struct HookServerTests {
    @Test func receivesAuthorizedEventsAndRejectsOthers() async throws {
        let received = Received()
        let port = UInt16.random(in: 20000..<40000)
        let server = HookServer(port: port, token: "secret") { event in await received.add(event) }
        try await server.start()
        defer { Task { await server.stop() } }

        let second = HookServer(port: port, token: "other") { _ in }
        await #expect(throws: (any Error).self) { try await second.start() }
        #expect(await !second.isListening)

        let url = URL(string: "http://127.0.0.1:\(port)/hook")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        request.setValue("devbox", forHTTPHeaderField: "X-Islet-Host")
        request.httpBody = Data(#"{"session_id":"s","hook_event_name":"Stop"}"#.utf8)
        let (body, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(body == Data("{}".utf8))
        #expect(await received.events == [HookEvent(kind: .stop, sessionID: "s", host: "devbox")])

        request.setValue("Bearer wrong", forHTTPHeaderField: "Authorization")
        let (_, unauthorized) = try await URLSession.shared.data(for: request)
        #expect((unauthorized as? HTTPURLResponse)?.statusCode == 401)

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

    actor Received {
        var events: [HookEvent] = []
        func add(_ event: HookEvent) { events.append(event) }
    }
}
