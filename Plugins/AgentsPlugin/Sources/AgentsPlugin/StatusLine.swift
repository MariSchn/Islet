import Foundation

struct StatusLineUpdate: Sendable, Equatable {
    var sessionID: String
    var sessionName: String?
    var usage: ClaudeUsage?

    struct Invalid: Error {}

    static func decode(_ data: Data) throws -> StatusLineUpdate {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionID = object["session_id"] as? String, !sessionID.isEmpty
        else { throw Invalid() }
        let name = (object["session_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let usage = (object["rate_limits"] as? [String: Any]).map { limits in
            ClaudeUsage(fiveHour: window(limits["five_hour"]), sevenDay: window(limits["seven_day"]))
        }
        return StatusLineUpdate(sessionID: sessionID, sessionName: name, usage: usage)
    }

    private static func window(_ value: Any?) -> UsageWindow? {
        guard let object = value as? [String: Any], let used = object["used_percentage"] as? Double else { return nil }
        let resetsAt = (object["resets_at"] as? Double).flatMap { (1...1e11).contains($0) ? Date(timeIntervalSince1970: $0) : nil }
        return UsageWindow(utilization: used, resetsAt: resetsAt)
    }
}

struct StatusLineInstaller: Sendable {
    enum State: Sendable, Equatable {
        case notInstalled
        case installed
        case outdated
        case replaced
    }

    struct InvalidStatusLine: Error, LocalizedError {
        var errorDescription: String? { "The statusLine setting in ~/.claude/settings.json is not an object" }
    }

    static let scriptName = "islet-statusline.sh"
    static let originalName = "islet-statusline.original"

    let directory: URL
    let port: UInt16
    let token: String

    var scriptURL: URL { directory.appending(path: Self.scriptName) }
    var originalURL: URL { directory.appending(path: Self.originalName) }
    private var settingsFile: SettingsFile {
        SettingsFile(url: directory.appending(path: "settings.json"), description: "~/\(directory.lastPathComponent)/settings.json")
    }
    private var command: String {
        "'" + scriptURL.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    var script: String {
        """
        #!/bin/sh
        input=$(cat)
        dir=$(dirname "$0")
        printf '%s' "$input" | curl -sf --connect-timeout 1 -m 2 -K /dev/fd/3 -X POST "http://127.0.0.1:\(port)\(HookServer.statusLinePath)" \\
          -H "Content-Type: application/json" \\
          -H "Expect:" \\
          -H "X-Islet-Agent: \(AgentSession.Agent.claudeCode.rawValue)" \\
          --data-binary @- >/dev/null 2>&1 3<<'ISLET_CONFIG' &
        header = "Authorization: Bearer \(token)"
        ISLET_CONFIG
        if [ -f "$dir/\(Self.originalName)" ]; then
          shell=$(command -v bash || echo sh)
          printf '%s' "$input" | "$shell" -c "$(cat "$dir/\(Self.originalName)")"
        fi

        """
    }

    var state: State {
        guard let configured = configuredCommand else { return .notInstalled }
        if Self.isOwn(configured) {
            return configured == command && (try? String(contentsOf: scriptURL, encoding: .utf8)) == script ? .installed : .outdated
        }
        return FileManager.default.fileExists(atPath: scriptURL.path) ? .replaced : .notInstalled
    }

    static func isOwn(_ command: String) -> Bool {
        command.contains(scriptName)
    }

    var originalCommand: String? {
        try? String(contentsOf: originalURL, encoding: .utf8)
    }

    private var configuredCommand: String? {
        ((try? settingsFile.read())?["statusLine"] as? [String: Any])?["command"] as? String
    }

    func install() throws {
        var settings = try settingsFile.read() ?? [:]
        guard settings["statusLine"] == nil || settings["statusLine"] is [String: Any] else { throw InvalidStatusLine() }
        var statusLine = settings["statusLine"] as? [String: Any] ?? [:]
        switch statusLine["command"] as? String {
        case let existing? where Self.isOwn(existing):
            break
        case let existing?:
            try Data(existing.utf8).write(to: originalURL, options: .atomic)
        case nil:
            try? FileManager.default.removeItem(at: originalURL)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: scriptURL.path, contents: Data(script.utf8), attributes: [.posixPermissions: 0o700]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        statusLine["type"] = "command"
        statusLine["command"] = command
        settings["statusLine"] = statusLine
        try settingsFile.write(settings)
    }

    func uninstall() throws {
        if var settings = try settingsFile.read(), var statusLine = settings["statusLine"] as? [String: Any], (statusLine["command"] as? String).map(Self.isOwn) == true {
            if let original = originalCommand {
                statusLine["command"] = original
                settings["statusLine"] = statusLine
            } else {
                settings["statusLine"] = nil
            }
            try settingsFile.write(settings)
        }
        try? FileManager.default.removeItem(at: scriptURL)
        try? FileManager.default.removeItem(at: originalURL)
    }
}
