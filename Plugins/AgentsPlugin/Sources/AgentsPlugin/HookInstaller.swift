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
        timeout="${1:-5}"
        tty=""
        pid=$$
        while [ "$pid" -gt 1 ]; do
          set -- $(ps -o ppid=,tty= -p "$pid" 2>/dev/null)
          [ -n "$1" ] || break
          case "$2" in ""|"?"|"??") ;; *) tty="/dev/$2" ;; esac
          pid=$1
        done
        curl -sf --connect-timeout 1 -m "$timeout" -X POST "http://127.0.0.1:\(port)\(HookServer.hookPath)" \\
          -H "Content-Type: application/json" \\
          -H "Expect:" \\
          -H "Authorization: Bearer \(token)" \\
          -H "X-Islet-Host: $(hostname -s 2>/dev/null || hostname)" \\
          -H "X-Islet-Terminal: ${__CFBundleIdentifier:-$TERM_PROGRAM}" \\
          -H "X-Islet-TTY: $tty" \\
          --data-binary @- 2>/dev/null
        exit 0

        """
    }

    public var remoteInstallCommand: String {
        "curl -sf -H 'Authorization: Bearer \(token)' http://127.0.0.1:\(port)\(HookServer.installPath) | sh"
    }

    public var sshConfigSnippet: String {
        "RemoteForward \(port) 127.0.0.1:\(port)"
    }

    public var remoteInstallScript: String {
        let entries = Self.events.reduce(into: [String: Any]()) { $0[$1] = Self.hookEntry(for: $1, script: Self.scriptPlaceholder) }
        let data = try! JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys, .withoutEscapingSlashes])
        return """
        #!/bin/sh
        set -e
        dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
        script="$dir/\(Self.scriptName)"
        command -v python3 >/dev/null 2>&1 || { echo "Islet: python3 is required to update $dir/settings.json" >&2; exit 1; }
        mkdir -p "$dir"
        cat > "$script" <<'ISLET_HOOK'
        \(script.trimmingCharacters(in: .newlines))
        ISLET_HOOK
        chmod 700 "$script"
        python3 - "$dir/settings.json" "$script" <<'ISLET_SETTINGS'
        import json, os, sys
        path, script = sys.argv[1], sys.argv[2]
        entries = json.loads(\(Self.pythonLiteral(String(decoding: data, as: UTF8.self))).replace("\(Self.scriptPlaceholder)", script))
        settings = {}
        if os.path.exists(path):
            with open(path) as f:
                text = f.read()
            settings = json.loads(text) if text.strip() else {}
        if not isinstance(settings, dict):
            sys.exit(f"Islet: {path} is not a JSON object")
        hooks = settings.setdefault("hooks", {})
        for event, entry in entries.items():
            groups = [g for g in hooks.get(event, []) if not any("\(Self.scriptName)" in h.get("command", "") for h in g.get("hooks", []))]
            groups.append({"hooks": [entry]})
            hooks[event] = groups
        with open(path, "w") as f:
            json.dump(settings, f, indent=2, sort_keys=True)
            f.write("\\n")
        ISLET_SETTINGS
        echo "Islet hooks installed in $dir. Restart Claude Code sessions on this machine to report them."

        """
    }

    private static let scriptPlaceholder = "__ISLET_SCRIPT__"

    private static func pythonLiteral(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") + "'"
    }

    public var isInstalled: Bool {
        hasAllHooks && isScriptCurrent
    }

    public var needsUpgrade: Bool {
        (hasAllHooks || FileManager.default.fileExists(atPath: scriptURL.path)) && !isInstalled
    }

    private var hasAllHooks: Bool {
        guard let settings = try? readSettings(), let hooks = settings["hooks"] as? [String: Any] else { return false }
        return Self.events.allSatisfy { Self.containsHook(hooks[$0]) }
    }

    private var isScriptCurrent: Bool {
        (try? String(contentsOf: scriptURL, encoding: .utf8)) == script
    }

    public func install() throws {
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        var settings = try readSettings() ?? [:]
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in Self.events {
            var groups = Self.withoutIsletHooks(hooks[event])
            groups.append(["hooks": [Self.hookEntry(for: event, script: scriptURL.path)]])
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

    static func hookEntry(for event: String, script: String) -> [String: Any] {
        let blocking = event == "PermissionRequest"
        let quoted = "'" + script.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let command = blocking ? "\(quoted) \(Int(HookServer.replyTimeout.components.seconds))" : quoted
        return ["type": "command", "command": command, "timeout": blocking ? Int(HookServer.replyTimeout.components.seconds) + 5 : 10]
    }

    private static func containsHook(_ groups: Any?) -> Bool {
        let all = groups as? [[String: Any]] ?? []
        return withoutIsletHooks(all).count < all.count
    }

    private static func withoutIsletHooks(_ groups: Any?) -> [[String: Any]] {
        (groups as? [[String: Any]] ?? []).filter { group in
            let commands = (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
            return !commands.contains { $0.contains(scriptName) }
        }
    }

    public struct UnreadableSettings: Error, LocalizedError {
        public var errorDescription: String? { "~/.claude/settings.json is not a JSON object" }
    }

    private func readSettings() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return nil }
        let data = try Data(contentsOf: settingsURL)
        if String(decoding: data, as: UTF8.self).allSatisfy(\.isWhitespace) { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw UnreadableSettings() }
        return object
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
    }
}
