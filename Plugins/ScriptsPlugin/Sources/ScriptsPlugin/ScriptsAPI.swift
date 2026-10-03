import Foundation
import IsletCore

@MainActor
final class ScriptsAPI {
    static let activityPath = "/activity"
    static let announcePath = "/announce"

    var token: String
    var isAccepting = false
    private let store: ScriptActivityStore
    private let announce: @MainActor (PillAnnouncement) -> Void

    init(token: String, store: ScriptActivityStore, announce: @escaping @MainActor (PillAnnouncement) -> Void) {
        self.token = token
        self.store = store
        self.announce = announce
    }

    func respond(to request: HTTPRequest) -> HTTPResponse {
        guard isAccepting else {
            return Self.error(503, "not active")
        }
        guard request.bearerToken == token else {
            return Self.error(401, "unauthorized")
        }
        let path = request.path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? request.path
        switch (request.method, path) {
        case ("POST", Self.activityPath):
            do {
                store.upsert(try ScriptActivityRequest.decode(request.body))
                return .json()
            } catch {
                return Self.invalid(error)
            }
        case ("POST", Self.announcePath):
            do {
                let announcement = try ScriptAnnounceRequest.decode(request.body)
                announce(PillAnnouncement(text: announcement.text, systemImage: ScriptSymbol.resolved(announcement.symbol), priority: announcement.priority))
                return .json()
            } catch {
                return Self.invalid(error)
            }
        case ("DELETE", _) where path.hasPrefix(Self.activityPath + "/"):
            store.remove(id: String(path.dropFirst(Self.activityPath.count + 1)))
            return .json()
        default:
            return Self.error(404, "not found")
        }
    }

    private static func invalid(_ error: any Error) -> HTTPResponse {
        self.error(400, (error as? ScriptRequestError)?.message ?? "invalid request")
    }

    private static func error(_ status: Int, _ message: String) -> HTTPResponse {
        let body = (try? JSONSerialization.data(withJSONObject: ["error": message])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return .json(status, body)
    }
}
