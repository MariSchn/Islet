import Foundation
import Network

public actor LocalHTTPServer {
    public typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse
    public typealias Authorizer = @Sendable (HTTPRequest) async -> Bool

    private struct Client {
        let connection: NWConnection
        var timeout: Task<Void, Never>?
        var work: Task<Void, Never>?
    }

    public nonisolated let port: UInt16
    private let maxBodySize: Int
    private let requestTimeout: Duration
    private let replyTimeout: Duration
    private let maxConnections: Int
    private var handler: Handler?
    private var authorizer: Authorizer?
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: Client] = [:]
    private let queue: DispatchQueue

    public init(port: UInt16, maxBodySize: Int = 1 << 20, requestTimeout: Duration = .seconds(10), replyTimeout: Duration = .seconds(60), maxConnections: Int = 64) {
        self.port = port
        self.maxBodySize = maxBodySize
        self.requestTimeout = requestTimeout
        self.replyTimeout = replyTimeout
        self.maxConnections = maxConnections
        self.queue = DispatchQueue(label: "islet.local-http-server.\(port)")
    }

    public var isListening: Bool {
        listener != nil
    }

    public func start(authorize: Authorizer? = nil, handler: @escaping Handler) async throws {
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
        self.authorizer = authorize
        self.listener = listener

        do {
            try await waitUntilReady(listener)
        } catch {
            if self.listener === listener {
                self.listener = nil
                self.handler = nil
                self.authorizer = nil
            }
            throw error
        }
        guard self.listener === listener else { throw CancellationError() }
    }

    public func stop() async {
        for id in clients.keys {
            close(id)
        }
        guard let listener else { return }
        self.listener = nil
        handler = nil
        authorizer = nil
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumed = Resumed()
            let previous = listener.stateUpdateHandler
            listener.stateUpdateHandler = { state in
                previous?(state)
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
                case .cancelled:
                    if resumed.claim() { continuation.resume(throwing: CancellationError()) }
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
        guard clients.count < maxConnections else {
            connection.cancel()
            return
        }
        let id = ObjectIdentifier(connection)
        clients[id] = Client(connection: connection, timeout: closeTask(for: id, after: requestTimeout))
        connection.start(queue: queue)
        receiveHead(on: connection, buffer: Data())
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

    private nonisolated func receiveHead(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [self] data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            switch HTTPRequest.parseHead(buffer) {
            case .complete(let request, let length, let bodyStart):
                let received = buffer.dropFirst(bodyStart).prefix(length)
                Task { await self.authorize(request, contentLength: length, received: Data(received), on: connection) }
            case .invalid:
                Task { await self.send(.json(400, #"{"error":"bad request"}"#), on: connection) }
            case .incomplete:
                if error != nil || isComplete {
                    Task { await self.close(connection) }
                } else {
                    self.receiveHead(on: connection, buffer: buffer)
                }
            }
        }
    }

    private func authorize(_ request: HTTPRequest, contentLength: Int, received: Data, on connection: NWConnection) async {
        if let authorizer, !(await authorizer(request)) {
            reject(.json(401, #"{"error":"unauthorized"}"#), on: connection, remaining: contentLength - received.count)
            return
        }
        guard clients[ObjectIdentifier(connection)] != nil else { return }
        guard contentLength <= maxBodySize else {
            reject(.json(413, #"{"error":"payload too large"}"#), on: connection, remaining: contentLength - received.count)
            return
        }
        let body = BodyBuffer(capacity: contentLength)
        body.data.append(received)
        if body.data.count >= contentLength {
            var request = request
            request.body = body.data
            handle(request, on: connection)
        } else {
            receiveBody(on: connection, request: request, body: body, length: contentLength)
        }
    }

    private nonisolated func receiveBody(on connection: NWConnection, request: HTTPRequest, body: BodyBuffer, length: Int) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [self] data, _, isComplete, error in
            if let data { body.data.append(data.prefix(length - body.data.count)) }
            if body.data.count >= length {
                var request = request
                request.body = body.data
                Task { await self.handle(request, on: connection) }
            } else if error != nil || isComplete {
                Task { await self.close(connection) }
            } else {
                self.receiveBody(on: connection, request: request, body: body, length: length)
            }
        }
    }

    private nonisolated func reject(_ response: HTTPResponse, on connection: NWConnection, remaining: Int) {
        guard remaining > 0 else {
            Task { await self.send(response, on: connection) }
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [self] data, _, isComplete, error in
            if error != nil || isComplete {
                Task { await self.close(connection) }
            } else {
                self.reject(response, on: connection, remaining: remaining - (data?.count ?? 0))
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

private final class BodyBuffer: @unchecked Sendable {
    var data = Data()

    init(capacity: Int) {
        data.reserveCapacity(capacity)
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
