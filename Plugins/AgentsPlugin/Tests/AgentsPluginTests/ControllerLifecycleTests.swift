import Foundation
import Testing
@testable import AgentsPlugin

@MainActor
@Suite(.serialized)
struct ControllerLifecycleTests {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ControllerLifecycleTests." + UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func turningThePluginOffLeavesPendingRequestsWaitingInTheTerminal() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let port = try freePort()
        let controller = AgentsController(token: "t", home: directory, port: port, storageDirectory: directory)
        await controller.start()
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(HookServer.hookPath)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer t", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"make"}}"#.utf8)
        let hook = Task { [request] in try? await URLSession.shared.data(for: request) }
        try await waitUntil { controller.store.sessions.first?.pendingRequest != nil }

        await controller.stop()
        _ = await hook.value
        try await Task.sleep(for: .milliseconds(100))

        let waiting = AgentSession.State.needsAttention("Waiting for your answer in the terminal")
        #expect(controller.store.sessions.first?.pendingRequests.isEmpty == true)
        #expect(controller.store.sessions.first?.state == waiting)
        #expect(SessionPersistence(directory: directory).load()?.sessions.first?.state == waiting)
    }

    @Test func interruptionsAreSeenRightAfterTheControllerRestarts() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transcript = directory.appending(path: "transcript.jsonl")
        try Data("{}\n".utf8).write(to: transcript)
        let controller = AgentsController(token: "t", home: directory, port: 0)
        await controller.start()
        controller.store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "s", transcriptPath: transcript.path, prompt: "build"))
        controller.sessionsDidChange()

        await controller.stop()
        await controller.start()
        let handle = try FileHandle(forWritingTo: transcript)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((InterruptionMonitorTests.interrupted + "\n").utf8))
        try handle.close()
        controller.interruptions.poll()

        #expect(controller.store.sessions.first?.state == .interrupted)
        await controller.stop()
    }

    @Test func costsReportedOnlyThroughTheStatusLineAreNotCountedAgainAfterARelaunch() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let noon = try #require(Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now))
        let first = AgentsController(token: "t", home: directory, port: 0, usage: UsageMonitor(now: { noon }), storageDirectory: directory)
        first.usage.record(sessionID: "status-line-only", cost: 5, sessionDuration: .seconds(60))
        await first.stop()

        let second = AgentsController(token: "t", home: directory, port: 0, usage: UsageMonitor(now: { noon }), storageDirectory: directory)
        await second.start()
        #expect(second.dailyCost == 5)
        second.usage.record(sessionID: "status-line-only", cost: 5.5, sessionDuration: .seconds(120))
        #expect(second.dailyCost == 5.5)
        await second.stop()
    }

    @Test func aContextAlertDoesNotReplaceANeedsYouAnnouncement() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = AgentsController(token: "t", home: directory, port: 0)
        controller.store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "a", prompt: "Deploy"))
        controller.sessionsDidChange()

        controller.store.apply(HookEvent(kind: .notification, sessionID: "a", message: "Claude needs your permission", notificationType: "permission_prompt"))
        controller.store.applyStatusLine(StatusLineUpdate(sessionID: "a", details: SessionDetails(contextPercentage: 90)))
        let announcement = try #require(controller.sessionsDidChange())

        #expect(announcement.priority == .attention)
        #expect(announcement.text.hasSuffix("Claude needs your permission"))
    }

    private func freePort() throws -> UInt16 {
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
}
