import CryptoKit
import Foundation
import IsletCore

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

    let port: UInt16
    let token: String
    private(set) var remoteToken: String?
    private(set) var installScript: String?
    private let installCodeLifetime: Duration
    private var installCodes: [String: ContinuousClock.Instant] = [:]
    private var antigravityParents: [String: String?] = [:]
    private let handler: Handler
    private let statusLineHandler: StatusLineHandler?
    private let server: LocalHTTPServer

    init(port: UInt16 = HookServer.defaultPort, token: String, remoteToken: String? = nil, installScript: String? = nil, installCodeLifetime: Duration = HookServer.installCodeLifetime, statusLineHandler: StatusLineHandler? = nil, handler: @escaping Handler) {
        self.port = port
        self.token = token
        self.remoteToken = remoteToken
        self.installScript = installScript
        self.installCodeLifetime = installCodeLifetime
        self.statusLineHandler = statusLineHandler
        self.handler = handler
        self.server = LocalHTTPServer(port: port, maxBodySize: Self.maxBodySize, requestTimeout: Self.requestTimeout, replyTimeout: Self.replyTimeout)
    }

    func start() async throws {
        try await server.start { [weak self] request in
            await self?.isAuthorized(request) ?? false
        } handler: { [weak self] request in
            guard let self else { return .json(404, #"{"error":"not found"}"#) }
            return await self.respond(to: request)
        }
    }

    func stop() async {
        await server.stop()
    }

    var isListening: Bool {
        get async { await server.isListening }
    }

    static func makeToken() -> String {
        (0..<32).map { _ in "0123456789abcdef".randomElement()! }.reduce(into: "") { $0.append($1) }
    }

    func issueInstallCode() -> String {
        let code = Self.makeToken()
        installCodes = [code: .now + installCodeLifetime]
        return code
    }

    func setRemoteAccess(token: String, installScript: String) {
        remoteToken = token
        self.installScript = installScript
        installCodes = [:]
    }

    var installScriptHash: String? {
        installScript.map(Self.hash)
    }

    static func hash(_ script: String) -> String {
        SHA256.hash(data: Data(script.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func isAuthorized(_ request: HTTPRequest) -> Bool {
        if request.hasBearerToken(token) || remoteToken.map(request.hasBearerToken) == true { return true }
        guard request.method == "GET", request.path == Self.installPath, let presented = request.bearerToken, let expiry = installCodes.removeValue(forKey: presented) else { return false }
        return expiry > .now
    }

    private func antigravityParent(at path: String) -> String? {
        if let parent = antigravityParents[path] { return parent }
        guard let line = TranscriptReader.firstLine(at: path) else { return nil }
        let parent = TranscriptReader.antigravityParent(in: line)
        antigravityParents[path] = .some(parent)
        return parent
    }

    private func respond(to request: HTTPRequest) async -> HTTPResponse {
        let isRemote = remoteToken.map(request.hasBearerToken) == true
        if request.method == "GET", request.path == Self.installPath {
            guard !isRemote, !request.hasBearerToken(token), let installScript else { return .json(404, #"{"error":"not found"}"#) }
            return .text(installScript)
        }
        if request.method == "POST", request.path == Self.statusLinePath, let statusLineHandler {
            guard let update = try? StatusLineUpdate.decode(request.body) else {
                return .json(400, #"{"error":"invalid status line payload"}"#)
            }
            await statusLineHandler(update)
            return .json(200)
        }
        guard request.method == "POST", request.path == Self.hookPath else {
            return .json(404, #"{"error":"not found"}"#)
        }
        guard let event = try? HookEvent.decode(request.body, agent: request.headers["x-islet-agent"], eventName: request.headers["x-islet-event"], host: request.headers["x-islet-host"], isRemote: isRemote, terminal: request.headers["x-islet-terminal"], tty: request.headers["x-islet-tty"], pid: request.headers["x-islet-pid"], tmux: request.headers["x-islet-tmux"], tmuxPane: request.headers["x-islet-tmux-pane"], title: request.headers["x-islet-title"], branch: request.headers["x-islet-branch"], parent: antigravityParent(at:)) else {
            return .json(400, #"{"error":"invalid hook payload"}"#)
        }
        let reply = await handler(event)
        return .json(200, reply.body)
    }
}

struct HookReply: Sendable, Equatable {
    static let empty = HookReply(body: "{}")

    var body: String
}
