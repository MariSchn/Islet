import Foundation
import Network

public actor LocalHTTPServer {
    public typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    private struct Client {
        let connection: NWConnection
        var timeout: Task<Void, Never>?
        var work: Task<Void, Never>?
    }

    public nonisolated let port: UInt16
    private let maxBodySize: Int
    private let requestTimeout: Duration
    private let replyTimeout: Duration
    private var handler: Handler?
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: Client] = [:]
    private let queue: DispatchQueue

    public init(port: UInt16, maxBodySize: Int = 16 << 20, requestTimeout: Duration = .seconds(10), replyTimeout: Duration = .seconds(60)) {
        self.port = port
        self.maxBodySize = maxBodySize
        self.requestTimeout = requestTimeout
        self.replyTimeout = replyTimeout
        self.queue = DispatchQueue(label: "islet.local-http-server.\(port)")
    }

    public var isListening: Bool {
        listener != nil
    }

    public func start(handler: @escaping Handler) async throws {
        guard listener == nil else { return }
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { throw URLError(.badURL) }
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: endpointPort)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.accept(connection) }
        }
        self.handler = handler
        self.listener = listener

        do {
            try await waitUntilReady(listener)
        } catch {
            self.listener = nil
            self.handler = nil
            throw error
        }
    }

    public func stop() async {
        for id in clients.keys {
            close(id)
        }
        guard let listener else { return }
        self.listener = nil
        handler = nil
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumed = Resumed()
            listener.stateUpdateHandler = { state in
                if case .cancelled = state, resumed.claim() { continuation.resume() }
            }
            listener.cancel()
        }
    }

    private func waitUntilReady(_ listener: NWListener) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let resumed = Resumed()
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if resumed.claim() { continuation.resume() }
                case .failed(let error), .waiting(let error):
                    listener.cancel()
                    if resumed.claim() {
                        continuation.resume(throwing: error)
                    } else if let self {
                        Task { await self.listenerDidFail() }
                    }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    private func listenerDidFail() {
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        clients[id] = Client(connection: connection, timeout: closeTask(for: id, after: requestTimeout))
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func closeTask(for id: ObjectIdentifier, after delay: Duration) -> Task<Void, Never> {
        Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            close(id)
        }
    }

    private func close(_ connection: NWConnection) {
        close(ObjectIdentifier(connection))
    }

    private func close(_ id: ObjectIdentifier) {
        guard let client = clients.removeValue(forKey: id) else { return }
        client.timeout?.cancel()
        client.work?.cancel()
        client.connection.cancel()
    }

    private func handle(_ request: HTTPRequest, on connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        guard var client = clients[id], let handler else { return }
        client.timeout?.cancel()
        client.timeout = closeTask(for: id, after: replyTimeout)
        client.work = Task { [weak self] in
            let response = await handler(request)
            guard !Task.isCancelled else { return }
            await self?.send(response, on: connection)
        }
        clients[id] = client
        watchForDisconnect(on: connection)
    }

    private nonisolated func watchForDisconnect(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [self] _, _, isComplete, error in
            if error != nil || isComplete {
                Task { await self.close(connection) }
            } else {
                self.watchForDisconnect(on: connection)
            }
        }
    }

    private nonisolated func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [self] data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            switch HTTPRequest.parse(buffer, maxBodySize: maxBodySize) {
            case .complete(let request):
                Task { await self.handle(request, on: connection) }
            case .invalid:
                Task { await self.send(.json(400, #"{"error":"bad request"}"#), on: connection) }
            case .tooLarge(let remaining):
                self.drain(on: connection, remaining: remaining)
            case .incomplete:
                if error != nil || isComplete {
                    Task { await self.close(connection) }
                } else {
                    self.receive(on: connection, buffer: buffer)
                }
            }
        }
    }

    private nonisolated func drain(on connection: NWConnection, remaining: Int) {
        guard remaining > 0 else {
            Task { await self.send(.json(413, #"{"error":"payload too large"}"#), on: connection) }
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [self] data, _, isComplete, error in
            if error != nil || isComplete {
                Task { await self.close(connection) }
            } else {
                self.drain(on: connection, remaining: remaining - (data?.count ?? 0))
            }
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialized, completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            Task { await self.close(connection) }
        })
    }
}

private final class Resumed: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !value else { return false }
        value = true
        return true
    }
}
