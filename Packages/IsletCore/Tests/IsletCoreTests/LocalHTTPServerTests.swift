import Foundation
import Testing
@testable import IsletCore

@Suite(.serialized)
struct LocalHTTPServerTests {
    @Test func servesRequestsAndRestarts() async throws {
        let port = try freePort()
        let server = LocalHTTPServer(port: port)
        try await server.start { request in
            .json(200, #"{"path":"\#(request.path)","body":"\#(String(decoding: request.body, as: UTF8.self))"}"#)
        }
        defer { Task { await server.stop() } }
        #expect(await server.isListening)
        #expect(server.port == port)

        let second = LocalHTTPServer(port: port)
        await #expect(throws: (any Error).self) { try await second.start { _ in .json() } }
        #expect(await !second.isListening)

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/echo")!)
        request.httpMethod = "POST"
        request.httpBody = Data("hello".utf8)
        let (body, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: body, as: UTF8.self) == #"{"path":"/echo","body":"hello"}"#)

        await server.stop()
        #expect(await !server.isListening)
        await #expect(throws: (any Error).self) { try await URLSession.shared.data(for: request) }

        try await server.start { _ in .json(204) }
        let (_, again) = try await URLSession.shared.data(for: request)
        #expect((again as? HTTPURLResponse)?.statusCode == 204)
    }

    @Test func rejectsInvalidAndOversizedRequests() async throws {
        let port = try freePort()
        let server = LocalHTTPServer(port: port, maxBodySize: 1024)
        let calls = Counter()
        try await server.start { _ in
            await calls.increment()
            return .json()
        }
        defer { Task { await server.stop() } }

        let invalid = try await rawRequest(port: port, "garbage\r\n\r\n")
        #expect(invalid.hasPrefix("HTTP/1.1 400"))

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/")!)
        request.httpMethod = "POST"
        request.httpBody = Data(repeating: UInt8(ascii: "x"), count: 2048)
        let (_, large) = try await URLSession.shared.data(for: request)
        #expect((large as? HTTPURLResponse)?.statusCode == 413)
        #expect(await calls.value == 0)
    }

    @Test func cancelsTheHandlerWhenTheClientLeaves() async throws {
        let gate = Gate()
        let port = try freePort()
        let server = LocalHTTPServer(port: port)
        try await server.start { _ in
            await gate.wait()
        }
        defer { Task { await server.stop() } }

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 1
        await #expect(throws: (any Error).self) { try await URLSession.shared.data(for: request) }
        let deadline = ContinuousClock.now + .seconds(5)
        while await gate.cancelled == 0 {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }

        request.timeoutInterval = 10
        let final = request
        async let response = URLSession.shared.data(for: final)
        try await Task.sleep(for: .milliseconds(200))
        await gate.open(with: .json(200, #"{"ok":true}"#))
        let (body, _) = try await response
        #expect(body == Data(#"{"ok":true}"#.utf8))

        let dropped = Task { try await URLSession.shared.data(for: final) }
        try await Task.sleep(for: .milliseconds(200))
        await server.stop()
        await #expect(throws: (any Error).self) { try await dropped.value }
        #expect(await gate.cancelled == 2)
    }

    @Test func closesIdleConnectionsAfterTheRequestTimeout() async throws {
        let port = try freePort()
        let server = LocalHTTPServer(port: port, requestTimeout: .milliseconds(200))
        try await server.start { _ in .json() }
        defer { Task { await server.stop() } }

        let closed = try await Task.detached { try Self.waitForClose(port: port) }.value
        #expect(closed)
    }

    private nonisolated static func waitForClose(port: UInt16) throws -> Bool {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        defer { Darwin.close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 }
        }
        try #require(connected)
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var byte: UInt8 = 0
        return Darwin.recv(fd, &byte, 1, 0) == 0
    }

    private func rawRequest(port: UInt16, _ text: String) async throws -> String {
        try await Task.detached {
            let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            defer { Darwin.close(fd) }
            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let connected = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 }
            }
            try #require(connected)
            var timeout = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            _ = text.withCString { Darwin.send(fd, $0, strlen($0), 0) }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.recv(fd, &buffer, buffer.count, 0)
            return String(decoding: buffer[..<max(count, 0)], as: UTF8.self)
        }.value
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

    actor Counter {
        var value = 0
        func increment() { value += 1 }
    }

    actor Gate {
        var cancelled = 0
        private var waiters: [CheckedContinuation<HTTPResponse, Never>] = []

        func wait() async -> HTTPResponse {
            await withTaskCancellationHandler {
                await withCheckedContinuation { waiters.append($0) }
            } onCancel: {
                Task { await self.cancel() }
            }
        }

        func open(with response: HTTPResponse) {
            waiters.forEach { $0.resume(returning: response) }
            waiters.removeAll()
        }

        private func cancel() {
            cancelled += 1
            open(with: .json())
        }
    }
}
