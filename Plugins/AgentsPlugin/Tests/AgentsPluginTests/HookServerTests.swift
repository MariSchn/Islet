import Foundation
import IsletCore
import Testing
@testable import AgentsPlugin

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

    @Test func installCodesFetchTheInstallScriptOnceAndExpire() async throws {
        let port = try freePort()
        let server = HookServer(port: port, token: "secret", installScript: "#!/bin/sh\n") { _ in .empty }
        try await server.start()
        defer { Task { await server.stop() } }
        let code = await server.issueInstallCode()
        #expect(code != "secret")

        var hook = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/hook")!)
        hook.httpMethod = "POST"
        hook.setValue("Bearer \(code)", forHTTPHeaderField: "Authorization")
        hook.httpBody = Data(#"{"session_id":"s","hook_event_name":"Stop"}"#.utf8)
        let (_, hookResponse) = try await URLSession.shared.data(for: hook)
        #expect((hookResponse as? HTTPURLResponse)?.statusCode == 401)

        var install = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/install")!)
        install.setValue("Bearer \(code)", forHTTPHeaderField: "Authorization")
        let (_, accepted) = try await URLSession.shared.data(for: install)
        #expect((accepted as? HTTPURLResponse)?.statusCode == 200)
        let (_, reused) = try await URLSession.shared.data(for: install)
        #expect((reused as? HTTPURLResponse)?.statusCode == 401)

        let expiringPort = try freePort()
        let expiring = HookServer(port: expiringPort, token: "secret", installScript: "#!/bin/sh\n", installCodeLifetime: .zero) { _ in .empty }
        try await expiring.start()
        defer { Task { await expiring.stop() } }
        var expired = URLRequest(url: URL(string: "http://127.0.0.1:\(expiringPort)/install")!)
        expired.setValue("Bearer \(await expiring.issueInstallCode())", forHTTPHeaderField: "Authorization")
        let (_, expiredResponse) = try await URLSession.shared.data(for: expired)
        #expect((expiredResponse as? HTTPURLResponse)?.statusCode == 401)
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

    @Test func forwardsStatusLineUpdates() async throws {
        let received = ReceivedUpdates()
        let port = try freePort()
        let server = HookServer(port: port, token: "secret") { update in
            await received.add(update)
        } handler: { _ in .empty }
        try await server.start()
        defer { Task { await server.stop() } }

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/statusline")!)
        request.httpMethod = "POST"
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"{"session_id":"s","session_name":"named","rate_limits":{"five_hour":{"used_percentage":12}}}"#.utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(await received.updates == [StatusLineUpdate(sessionID: "s", sessionName: "named", usage: ClaudeUsage(fiveHour: UsageWindow(utilization: 12, resetsAt: nil), sevenDay: nil))])

        request.httpBody = Data("{}".utf8)
        let (_, invalid) = try await URLSession.shared.data(for: request)
        #expect((invalid as? HTTPURLResponse)?.statusCode == 400)

        request.setValue("Bearer wrong", forHTTPHeaderField: "Authorization")
        let (_, unauthorized) = try await URLSession.shared.data(for: request)
        #expect((unauthorized as? HTTPURLResponse)?.statusCode == 401)
        #expect(await received.updates.count == 1)
    }

    actor ReceivedUpdates {
        var updates: [StatusLineUpdate] = []

        func add(_ update: StatusLineUpdate) {
            updates.append(update)
        }
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
