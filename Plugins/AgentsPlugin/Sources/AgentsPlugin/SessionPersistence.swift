import Foundation
import os

struct SessionSnapshot: Codable, Equatable {
    var sessions: [AgentSession]
    var hiddenSessions: [AgentSession]
}

struct SessionPersistence {
    let fileURL: URL
    let logger: Logger

    init(directory: URL, logger: Logger = Logger()) {
        fileURL = directory.appending(path: "sessions.json")
        self.logger = logger
    }

    func load() -> SessionSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try JSONDecoder().decode(SessionSnapshot.self, from: data)
        } catch {
            logger.error("Could not read \(fileURL.path, privacy: .public), keeping it aside: \(error, privacy: .public)")
            try? FileManager.default.moveItem(at: fileURL, to: fileURL.appendingPathExtension("corrupt"))
            return nil
        }
    }

    func save(_ snapshot: SessionSnapshot) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Could not write \(fileURL.path, privacy: .public): \(error, privacy: .public)")
        }
    }
}
