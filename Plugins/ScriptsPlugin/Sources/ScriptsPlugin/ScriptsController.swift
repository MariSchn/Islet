import Foundation
import IsletCore
import Observation
import os

@MainActor
@Observable
final class ScriptsController {
    static let defaultPort: UInt16 = 7366
    static let tokenFileName = "token"

    let store: ScriptActivityStore
    let port: UInt16
    let tokenFile: URL
    private(set) var token: String
    private(set) var serverError: String?

    @ObservationIgnored private let api: ScriptsAPI
    @ObservationIgnored private let server: LocalHTTPServer
    @ObservationIgnored private let saveToken: @MainActor (String) -> Void
    @ObservationIgnored private let logger: Logger

    init(token: String, storageDirectory: URL, port: UInt16 = ScriptsController.defaultPort, store: ScriptActivityStore = ScriptActivityStore(), announce: @escaping @MainActor (PillAnnouncement) -> Void, saveToken: @escaping @MainActor (String) -> Void, logger: Logger = Logger()) {
        self.token = token
        self.port = port
        self.store = store
        self.saveToken = saveToken
        self.logger = logger
        tokenFile = storageDirectory.appending(path: Self.tokenFileName)
        api = ScriptsAPI(token: token, store: store, announce: announce)
        server = LocalHTTPServer(port: port)
    }

    static func makeToken() -> String {
        (0..<32).map { _ in "0123456789abcdef".randomElement()! }.reduce(into: "") { $0.append($1) }
    }

    func start() async {
        writeTokenFile()
        api.isAccepting = true
        do {
            let api = api
            try await server.start { request in
                await api.respond(to: request)
            }
            serverError = nil
        } catch {
            serverError = "Could not listen on 127.0.0.1:\(port). Is another app using the port?"
        }
    }

    func stop() async {
        api.isAccepting = false
        await server.stop()
        store.removeAll()
    }

    func regenerateToken() {
        token = Self.makeToken()
        api.token = token
        saveToken(token)
        writeTokenFile()
    }

    private func writeTokenFile() {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: tokenFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? manager.removeItem(at: tokenFile)
            guard manager.createFile(atPath: tokenFile.path, contents: Data(token.utf8), attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenFile.path)
        } catch {
            logger.error("Could not write the token file: \(error.localizedDescription)")
        }
    }
}
