import Foundation
import Network

actor HookServer {
    typealias Handler = @Sendable (HookEvent) async -> HookReply
    typealias StatusLineHandler = @Sendable (StatusLineUpdate) async -> Void

    static let defaultPort: UInt16 = 7365
    static let hookPath = "/hook"
    static let installPath = "/install"
    static let statusLinePath = "/statusline"
    static let maxBodySize = 16 << 20
    static let requestTimeout: Duration = .seconds(10)
    static let replyTimeout: Duration = .seconds(600)
    static let installCodeLifetime: Duration = .seconds(600)

    private struct Client {
        let connection: NWConnection
        var timeout: Task<Void, Never>?
        var work: Task<Void, Never>?
    }

    let port: UInt16
    let token: String
    let installScript: String?
    private let installCodeLifetime: Duration
    private var installCodes: [String: ContinuousClock.Instant] = [:]
    private let handler: Handler
    private let statusLineHandler: StatusLineHandler?
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: Client] = [:]
    private let queue = DispatchQueue(label: "islet.agents.hook-server")

    init(port: UInt16 = HookServer.defaultPort, token: String, installScript: String? = nil, installCodeLifetime: Duration = HookServer.installCodeLifetime, statusLineHandler: StatusLineHandler? = nil, handler: @escaping Handler) {
        self.port = port
        self.token = token
        self.installScript = installScript
        self.installCodeLifetime = installCodeLifetime
        self.statusLineHandler = statusLineHandler
        self.handler = handler
    }

    func start() async throws {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.accept(connection) }
        }
        self.listener = listener

        do {
            try await waitUntilReady(listener)
        } catch {
            self.listener = nil
            throw error
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

    var isListening: Bool {
        listener != nil
    }

    static func makeToken() -> String {
        (0..<32).map { _ in "0123456789abcdef".randomElement()! }.reduce(into: "") { $0.append($1) }
    }

    func issueInstallCode() -> String {
        let now = ContinuousClock.now
        installCodes = installCodes.filter { $0.value > now }
        let code = Self.makeToken()
        installCodes[code] = now + installCodeLifetime
        return code
    }

    private func isAuthorized(_ request: HTTPRequest) -> Bool {
        guard let presented = request.bearerToken else { return false }
        if presented == token { return true }
        guard request.method == "GET", request.path == Self.installPath, let expiry = installCodes.removeValue(forKey: presented) else { return false }
        return expiry > .now
    }

    func stop() async {
        for id in clients.keys {
            close(id)
        }
        guard let listener else { return }
        self.listener = nil
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumed = Resumed()
            listener.stateUpdateHandler = { state in
                if case .cancelled = state, resumed.claim() { continuation.resume() }
            }
            listener.cancel()
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        clients[id] = Client(connection: connection, timeout: closeTask(for: id, after: Self.requestTimeout))
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
        guard var client = clients[id] else { return }
        client.timeout?.cancel()
        client.timeout = closeTask(for: id, after: Self.replyTimeout)
        client.work = Task { await respond(to: request, on: connection) }
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
            switch HTTPRequest.parse(buffer, maxBodySize: Self.maxBodySize) {
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

    private func respond(to request: HTTPRequest, on connection: NWConnection) async {
        let response: HTTPResponse
        if !isAuthorized(request) {
            response = .json(401, #"{"error":"unauthorized"}"#)
        } else if request.method == "GET", request.path == Self.installPath, let installScript {
            response = .text(installScript)
        } else if request.method == "POST", request.path == Self.statusLinePath, let statusLineHandler {
            guard let update = try? StatusLineUpdate.decode(request.body) else {
                send(.json(400, #"{"error":"invalid status line payload"}"#), on: connection)
                return
            }
            await statusLineHandler(update)
            guard !Task.isCancelled else { return }
            response = .json(200)
        } else if request.method != "POST" || request.path != Self.hookPath {
            response = .json(404, #"{"error":"not found"}"#)
        } else if let event = try? HookEvent.decode(request.body, agent: request.headers["x-islet-agent"], host: request.headers["x-islet-host"], terminal: request.headers["x-islet-terminal"], tty: request.headers["x-islet-tty"], pid: request.headers["x-islet-pid"], tmux: request.headers["x-islet-tmux"], tmuxPane: request.headers["x-islet-tmux-pane"], title: request.headers["x-islet-title"]) {
            let reply = await handler(event)
            guard !Task.isCancelled else { return }
            response = .json(200, reply.body)
        } else {
            response = .json(400, #"{"error":"invalid hook payload"}"#)
        }
        send(response, on: connection)
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialized, completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            Task { await self.close(connection) }
        })
    }
}

struct HookReply: Sendable, Equatable {
    static let empty = HookReply(body: "{}")

    var body: String

    init(body: String) {
        self.body = body
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
