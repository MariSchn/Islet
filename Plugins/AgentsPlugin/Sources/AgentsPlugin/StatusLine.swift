import Foundation

struct StatusLineUpdate: Sendable, Equatable {
    var sessionID: String
    var sessionName: String?
    var usage: ClaudeUsage?
    var antigravityQuota: AntigravityQuota?
    var details = SessionDetails()

    var isAntigravity: Bool { antigravityQuota != nil }

    struct Invalid: Error {}

    static func decode(_ data: Data) throws -> StatusLineUpdate {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionID = object["session_id"] as? String, !sessionID.isEmpty || object["product"] as? String == "antigravity"
        else { throw Invalid() }
        let name = string(object["session_name"]) ?? string(object["conversation_title"])
        let usage = (object["rate_limits"] as? [String: Any]).map { limits in
            ClaudeUsage(fiveHour: window(limits["five_hour"]), sevenDay: window(limits["seven_day"]))
        }
        let quota = object["product"] as? String == "antigravity" ? antigravityQuota(object["quota"]) : nil
        return StatusLineUpdate(sessionID: sessionID, sessionName: name, usage: usage, antigravityQuota: quota, details: details(from: object))
    }

    private static func details(from object: [String: Any]) -> SessionDetails {
        let context = object["context_window"] as? [String: Any]
        let model = object["model"] as? [String: Any]
        let effort = string((object["effort"] as? [String: Any])?["level"]) ?? string(model?["effort"])
        return SessionDetails(
            contextPercentage: double(context?["used_percentage"]),
            model: string(model?["display_name"]).map { SessionDetails.modelName($0, without: effort) },
            effort: effort,
            fastMode: object["fast_mode"] as? Bool,
            worktree: worktree(from: object),
            pullRequest: pullRequest(from: object),
            costUSD: costUSD(from: object),
            linesAdded: linesAdded(from: object),
            linesRemoved: linesRemoved(from: object),
            duration: duration(from: object)
        )
    }

    private static func costObject(_ object: [String: Any]) -> [String: Any]? {
        object["cost"] as? [String: Any]
    }

    private static func costUSD(from object: [String: Any]) -> Double? {
        double(object["cost"]) ?? double(costObject(object)?["total_cost_usd"])
    }

    private static func linesAdded(from object: [String: Any]) -> Int? {
        integer(costObject(object)?["total_lines_added"])
    }

    private static func linesRemoved(from object: [String: Any]) -> Int? {
        integer(costObject(object)?["total_lines_removed"])
    }

    private static func duration(from object: [String: Any]) -> Duration? {
        double(costObject(object)?["total_duration_ms"]).map { Duration.milliseconds($0) }
    }

    private static func worktree(from object: [String: Any]) -> String? {
        if let name = string((object["worktree"] as? [String: Any])?["name"]) { return name }
        return string((object["workspace"] as? [String: Any])?["git_worktree"])
    }

    private static func pullRequest(from object: [String: Any]) -> SessionDetails.PullRequest? {
        guard let pr = object["pr"] as? [String: Any], let number = integer(pr["number"]) else { return nil }
        return SessionDetails.PullRequest(
            number: number,
            url: string(pr["url"]),
            reviewState: string(pr["review_state"]),
            isMergeRequest: (pr["kind"] as? String) == "mr"
        )
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.intValue
    }

    private static func string(_ value: Any?) -> String? {
        (value as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func double(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }

    private static func window(_ value: Any?) -> UsageWindow? {
        guard let object = value as? [String: Any], let used = object["used_percentage"] as? Double else { return nil }
        let resetsAt = (object["resets_at"] as? Double).flatMap { (1...1e11).contains($0) ? Date(timeIntervalSince1970: $0) : nil }
        return UsageWindow(utilization: used, resetsAt: resetsAt)
    }

    private static func antigravityQuota(_ value: Any?) -> AntigravityQuota {
        let buckets = (value as? [String: Any] ?? [:]).compactMap { name, value -> AntigravityQuota.Bucket? in
            guard let object = value as? [String: Any], let remaining = double(object["remaining_fraction"]) else { return nil }
            let resetsAt = string(object["reset_time"]).flatMap { try? Date($0, strategy: .iso8601) }
            return AntigravityQuota.Bucket(name: name, window: UsageWindow(utilization: (1 - remaining) * 100, resetsAt: resetsAt))
        }
        return AntigravityQuota(buckets: buckets.sorted { $0.name < $1.name })
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
        var settingsDescription: String
        var errorDescription: String? { "The statusLine setting in \(settingsDescription) is not an object" }
    }

    static let scriptName = "islet-statusline.sh"
    static let originalName = "islet-statusline.original"

    let agent: AgentSession.Agent
    let directory: URL
    let port: UInt16
    let token: String

    init(agent: AgentSession.Agent = .claudeCode, directory: URL, port: UInt16, token: String) {
        self.agent = agent
        self.directory = directory
        self.port = port
        self.token = token
    }

    var scriptURL: URL { directory.appending(path: Self.scriptName) }
    var originalURL: URL { directory.appending(path: Self.originalName) }
    private var settingsDescription: String {
        switch agent {
        case .claudeCode, .codex: "~/\(directory.lastPathComponent)/settings.json"
        case .antigravity: "~/.gemini/\(directory.lastPathComponent)/settings.json"
        }
    }
    private var settingsFile: SettingsFile {
        SettingsFile(url: directory.appending(path: "settings.json"), description: settingsDescription)
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
          -H "X-Islet-Agent: \(agent.rawValue)" \\
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
        guard settings["statusLine"] == nil || settings["statusLine"] is [String: Any] else { throw InvalidStatusLine(settingsDescription: settingsDescription) }
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
