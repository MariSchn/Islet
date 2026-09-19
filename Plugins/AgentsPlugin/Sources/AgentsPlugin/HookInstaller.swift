import Foundation

public struct HookInstaller: Sendable {
    public static let events = ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Notification", "Stop"]
    public static let scriptName = "islet-hook.sh"

    public let claudeDirectory: URL
    public let port: UInt16
    public let token: String

    public init(claudeDirectory: URL, port: UInt16, token: String) {
        self.claudeDirectory = claudeDirectory
        self.port = port
        self.token = token
    }

    public var scriptURL: URL { claudeDirectory.appending(path: Self.scriptName) }
    public var settingsURL: URL { claudeDirectory.appending(path: "settings.json") }

    public var script: String {
        """
        #!/bin/sh
        curl -sS -m 5 -X POST "http://127.0.0.1:\(port)\(HookServer.hookPath)" \\
          -H "Content-Type: application/json" \\
          -H "Authorization: Bearer \(token)" \\
          -H "X-Islet-Host: $(hostname -s 2>/dev/null || hostname)" \\
          --data-binary @- 2>/dev/null
        exit 0

        """
    }

    public var isInstalled: Bool {
        guard let settings = try? readSettings(), let hooks = settings["hooks"] as? [String: Any] else { return false }
        let hasAllEvents = Self.events.allSatisfy { Self.containsHook(hooks[$0]) }
        let script = try? String(contentsOf: scriptURL, encoding: .utf8)
        return hasAllEvents && script == self.script
    }

    public func install() throws {
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        var settings = try readSettings() ?? [:]
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in Self.events {
            var groups = Self.withoutIsletHooks(hooks[event])
            groups.append(["hooks": [["type": "command", "command": scriptURL.path, "timeout": 10]]])
            hooks[event] = groups
        }
        settings["hooks"] = hooks
        try writeSettings(settings)
    }

    public func uninstall() throws {
        if var settings = try readSettings(), var hooks = settings["hooks"] as? [String: Any] {
            for event in hooks.keys {
                let groups = Self.withoutIsletHooks(hooks[event])
                hooks[event] = groups.isEmpty ? nil : groups
            }
            settings["hooks"] = hooks.isEmpty ? nil : hooks
            try writeSettings(settings)
        }
        try? FileManager.default.removeItem(at: scriptURL)
    }

    private static func containsHook(_ groups: Any?) -> Bool {
        let all = groups as? [[String: Any]] ?? []
        return withoutIsletHooks(all).count < all.count
    }

    private static func withoutIsletHooks(_ groups: Any?) -> [[String: Any]] {
        (groups as? [[String: Any]] ?? []).filter { group in
            let commands = (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
            return !commands.contains { $0.hasSuffix(scriptName) }
        }
    }

    private func readSettings() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return nil }
        let data = try Data(contentsOf: settingsURL)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: .atomic)
    }
}
