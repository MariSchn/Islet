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
        let resetsAt = (object["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
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
        {
          body=$(mktemp) || exit 0
          printf '%s' "$input" > "$body"
          curl -sf --connect-timeout 1 -m 2 -K - -X POST "http://127.0.0.1:\(port)\(HookServer.statusLinePath)" \\
            -H "Content-Type: application/json" \\
            -H "Expect:" \\
            -H "X-Islet-Agent: \(AgentSession.Agent.claudeCode.rawValue)" \\
            --data-binary "@$body" <<'ISLET_CONFIG'
        header = "Authorization: Bearer \(token)"
        ISLET_CONFIG
          rm -f "$body"
        } >/dev/null 2>&1 &
        if [ -f "$dir/\(Self.originalName)" ]; then
          printf '%s' "$input" | sh -c "$(cat "$dir/\(Self.originalName)")"
        fi

        """
    }

    var state: State {
        if configuredCommand == command {
            return (try? String(contentsOf: scriptURL, encoding: .utf8)) == script ? .installed : .outdated
        }
        return FileManager.default.fileExists(atPath: scriptURL.path) ? .replaced : .notInstalled
    }

    var originalCommand: String? {
        try? String(contentsOf: originalURL, encoding: .utf8)
    }

    private var configuredCommand: String? {
        ((try? settingsFile.read())?["statusLine"] as? [String: Any])?["command"] as? String
    }

    func install() throws {
        var settings = try settingsFile.read() ?? [:]
        var statusLine = settings["statusLine"] as? [String: Any] ?? [:]
        switch statusLine["command"] as? String {
        case command?:
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
        if var settings = try settingsFile.read(), var statusLine = settings["statusLine"] as? [String: Any], statusLine["command"] as? String == command {
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
