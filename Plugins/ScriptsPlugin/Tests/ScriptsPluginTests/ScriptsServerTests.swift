import Foundation
import IsletCore
import Testing
@testable import ScriptsPlugin

@MainActor
@Suite(.serialized)
struct ScriptsServerTests {
    final class Announcements {
        var items: [PillAnnouncement] = []
    }

    private func send(_ method: String, _ path: String, port: UInt16, token: String?, body: String? = nil) async throws -> (Int, String) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = body.map { Data($0.utf8) }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, String(decoding: data, as: UTF8.self))
    }

    @Test func servesTheActivityAndAnnounceApi() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ScriptsServerTests." + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let announcements = Announcements()
        let port = try freePort()
        let controller = ScriptsController(token: "secret", storageDirectory: directory, port: port, announce: { announcements.items.append($0) }, saveToken: { _ in })
        await controller.start()
        defer { Task { await controller.stop() } }
        #expect(controller.serverError == nil)

        let (unauthorized, _) = try await send("POST", "/activity", port: port, token: nil, body: #"{"id":"a","text":"x"}"#)
        #expect(unauthorized == 401)
        let (wrong, _) = try await send("POST", "/activity", port: port, token: "wrong", body: #"{"id":"a","text":"x"}"#)
        #expect(wrong == 401)
        #expect(controller.store.activities.isEmpty)

        let (created, createdBody) = try await send("POST", "/activity", port: port, token: "secret", body: #"{"id":"demo","text":"Compiling","progress":0.3}"#)
        #expect(created == 200)
        #expect(createdBody == "{}")
        #expect(controller.store.activities.map(\.text) == ["Compiling"])
        #expect(controller.store.activities.first?.progress == 0.3)

        let (deleted, _) = try await send("DELETE", "/activity/demo", port: port, token: "secret")
        #expect(deleted == 200)
        #expect(controller.store.activities.isEmpty)
        let (again, _) = try await send("DELETE", "/activity/demo", port: port, token: "secret")
        #expect(again == 200)

        let (bad, badBody) = try await send("POST", "/activity", port: port, token: "secret", body: #"{"id":"a"}"#)
        #expect(bad == 400)
        #expect(badBody.contains("error"))
        let (notJSON, _) = try await send("POST", "/activity", port: port, token: "secret", body: "nope")
        #expect(notJSON == 400)

        let (announced, _) = try await send("POST", "/announce", port: port, token: "secret", body: #"{"text":"Done","priority":"attention"}"#)
        #expect(announced == 200)
        #expect(announcements.items.map(\.text) == ["Done"])
        #expect(announcements.items.first?.priority == .attention)
        let (badAnnounce, _) = try await send("POST", "/announce", port: port, token: "secret", body: "{}")
        #expect(badAnnounce == 400)

        let (unknownPath, _) = try await send("POST", "/other", port: port, token: "secret", body: "{}")
        #expect(unknownPath == 404)
        let (unknownMethod, _) = try await send("GET", "/activity", port: port, token: "secret")
        #expect(unknownMethod == 404)
    }

    @Test func writesTheTokenFileAndRegeneratesTheToken() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ScriptsServerTests." + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let savedTokens = Announcements()
        let port = try freePort()
        let controller = ScriptsController(token: "secret", storageDirectory: directory, port: port, announce: { _ in }, saveToken: { savedTokens.items.append(PillAnnouncement(text: $0)) })
        await controller.start()
        defer { Task { await controller.stop() } }

        #expect(try String(contentsOf: controller.tokenFile, encoding: .utf8) == "secret")
        let permissions = try FileManager.default.attributesOfItem(atPath: controller.tokenFile.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)

        controller.regenerateToken()
        #expect(controller.token.count == 32)
        #expect(controller.token != "secret")
        #expect(savedTokens.items.map(\.text) == [controller.token])
        #expect(try String(contentsOf: controller.tokenFile, encoding: .utf8) == controller.token)
        let (old, _) = try await send("POST", "/activity", port: port, token: "secret", body: #"{"id":"a","text":"x"}"#)
        #expect(old == 401)
        let (fresh, _) = try await send("POST", "/activity", port: port, token: controller.token, body: #"{"id":"a","text":"x"}"#)
        #expect(fresh == 200)
    }

    @Test func reportsABusyPort() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ScriptsServerTests." + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let port = try freePort()
        let blocker = LocalHTTPServer(port: port)
        try await blocker.start { _ in .json() }
        defer { Task { await blocker.stop() } }
        let controller = ScriptsController(token: "secret", storageDirectory: directory, port: port, announce: { _ in }, saveToken: { _ in })
        await controller.start()
        #expect(controller.serverError != nil)
    }

    @Test func ignoresRequestsWhileInactive() {
        let store = ScriptActivityStore()
        let api = ScriptsAPI(token: "secret", store: store, announce: { _ in })
        let request = HTTPRequest(method: "POST", path: "/activity", headers: ["authorization": "Bearer secret"], body: Data(#"{"id":"a","text":"x"}"#.utf8))
        #expect(api.respond(to: request).status == 503)
        #expect(store.activities.isEmpty)
        api.isAccepting = true
        #expect(api.respond(to: request).status == 200)
        #expect(store.activities.count == 1)
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
