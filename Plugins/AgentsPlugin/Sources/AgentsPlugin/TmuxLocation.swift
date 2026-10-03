import Foundation

struct TmuxLocation: Sendable, Equatable, Codable {
    let socket: String
    let serverPID: Int32
    let pane: String

    init(socket: String, serverPID: Int32, pane: String) {
        self.socket = socket
        self.serverPID = serverPID
        self.pane = pane
    }

    init?(environment: String, pane: String) {
        let parts = environment.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count >= 2,
              let serverPID = Int32(parts[parts.count - 2]), serverPID > 1,
              pane.count > 1, pane.hasPrefix("%"), pane.dropFirst().allSatisfy({ $0.isASCII && $0.isNumber })
        else { return nil }
        let socket = parts.dropLast(2).joined(separator: ",")
        guard socket.hasPrefix("/"), HookEvent.isSafeIdentifier(socket) else { return nil }
        self.init(socket: socket, serverPID: serverPID, pane: pane)
    }
}
