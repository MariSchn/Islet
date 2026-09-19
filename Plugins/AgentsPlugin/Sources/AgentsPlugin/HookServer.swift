import Foundation
import Network

public actor HookServer {
    public typealias Handler = @Sendable (HookEvent) async -> Void

    public static let defaultPort: UInt16 = 7365
    public static let hookPath = "/hook"

    public let port: UInt16
    public let token: String
    private let handler: Handler
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "islet.agents.hook-server")

    public init(port: UInt16 = HookServer.defaultPort, token: String, handler: @escaping Handler) {
        self.port = port
        self.token = token
        self.handler = handler
    }

    public func start() throws {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.accept(connection) }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private nonisolated func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [self] data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            if let parsed = HTTPRequest.parse(buffer) {
                Task { await self.respond(to: parsed.request, on: connection) }
            } else if error != nil || isComplete || buffer.count > 4 << 20 {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) async {
        let response: HTTPResponse
        if request.bearerToken != token {
            response = .json(401, #"{"error":"unauthorized"}"#)
        } else if request.method != "POST" || request.path != Self.hookPath {
            response = .json(404, #"{"error":"not found"}"#)
        } else if let event = try? HookEvent.decode(request.body, host: request.headers["x-islet-host"]) {
            await handler(event)
            response = .json()
        } else {
            response = .json(400, #"{"error":"invalid hook payload"}"#)
        }
        connection.send(content: response.serialized, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
