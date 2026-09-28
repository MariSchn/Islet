import Foundation

struct HookInstaller: Sendable {
    static let scriptName = "islet-hook.sh"
    private static let scriptPlaceholder = "__ISLET_SCRIPT__"

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

    var events: [String] {
        switch agent {
        case .claudeCode: ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest", "PermissionDenied", "Notification", "Stop", "StopFailure"]
        case .codex: ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop"]
        }
    }

    var settingsFileName: String {
        switch agent {
        case .claudeCode: "settings.json"
        case .codex: "hooks.json"
        }
    }

    var settingsDescription: String {
        "~/\(directory.lastPathComponent)/\(settingsFileName)"
    }

    private var remoteDirectoryExpression: String {
        switch agent {
        case .claudeCode: "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
        case .codex: "${CODEX_HOME:-$HOME/.codex}"
        }
    }

    var scriptURL: URL { directory.appending(path: Self.scriptName) }
    var settingsURL: URL { directory.appending(path: settingsFileName) }

    var script: String {
        """
        #!/bin/sh
        timeout="${1:-5}"
        payload=$(cat)
        title=""
        transcript=""
        case "$(printf '%s' "$payload" | sed -n 's/.*"hook_event_name":"\\([A-Za-z]*\\)".*/\\1/p')" in
          PreToolUse|PostToolUse|PostToolUseFailure|PermissionDenied) ;;
          *) transcript=$(printf '%s' "$payload" | sed -n 's/.*"transcript_path":"\\([^"]*\\)".*/\\1/p') ;;
        esac
        if [ -n "$transcript" ] && [ -f "$transcript" ]; then
          titles=$(grep -oE '"(customTitle|aiTitle)":"([^"\\\\]|\\\\.)*"' "$transcript" 2>/dev/null)
          title=$(printf '%s\\n' "$titles" | grep '^"customTitle"' | tail -n 1)
          [ -n "$title" ] || title=$(printf '%s\\n' "$titles" | grep '^"aiTitle"' | tail -n 1)
          title=$(printf '%s' "$title" | sed 's/^"[A-Za-z]*":"//; s/"$//; s/\\\\"/"/g; s/\\\\\\\\/\\\\/g')
        fi
        terminal="${__CFBundleIdentifier:-$TERM_PROGRAM}"
        tty=""
        agent_pid=""
        pid=$$
        set -f
        while [ "$pid" -gt 1 ]; do
          set -- $(ps -o ppid=,tty=,comm= -p "$pid" 2>/dev/null)
          [ -n "$1" ] || break
          case "$2" in ""|"?"|"??") ;; *) tty="/dev/$2" ;; esac
          if [ -z "$agent_pid" ]; then
            case "${3##*/}" in claude|claude-*|node|bun|codex|codex-*|[0-9]*.[0-9]*.[0-9]*) agent_pid=$pid ;; esac
          fi
          if [ -z "$terminal" ] && [ "$(uname)" = Darwin ]; then
            vars=$(ps -E -o command= -p "$pid" 2>/dev/null | tr ' ' '\n')
            terminal=$(printf '%s\n' "$vars" | sed -n 's/^__CFBundleIdentifier=//p' | head -n 1)
            [ -n "$terminal" ] || terminal=$(printf '%s\n' "$vars" | sed -n 's/^TERM_PROGRAM=//p' | head -n 1)
          fi
          pid=$1
        done
        case "$terminal" in vscode) case "$VSCODE_GIT_ASKPASS_MAIN" in *[Cc]ursor*) terminal=cursor ;; esac ;; esac
        body=$(mktemp) || exit 0
        request=""
        trap '[ -n "$request" ] && kill "$request" 2>/dev/null; rm -f "$body"; exit 0' HUP INT TERM
        printf '%s' "$payload" > "$body"
        curl -sf --connect-timeout 1 -m "$timeout" -K - -X POST "http://127.0.0.1:\(port)\(HookServer.hookPath)" \\
          -H "Content-Type: application/json" \\
          -H "Expect:" \\
          -H "X-Islet-Agent: \(agent.rawValue)" \\
          -H "X-Islet-Host: $(hostname -s 2>/dev/null || hostname)" \\
          -H "X-Islet-Terminal: $terminal" \\
          -H "X-Islet-TTY: $tty" \\
          -H "X-Islet-PID: $agent_pid" \\
          -H "X-Islet-Title: $title" \\
          --data-binary "@$body" 2>/dev/null <<'ISLET_CONFIG' &
        header = "Authorization: Bearer \(token)"
        ISLET_CONFIG
        request=$!
        wait "$request"
        request=""
        rm -f "$body"
        exit 0

        """
    }

    var remoteInstallCommand: String {
        "curl -sf -H 'Authorization: Bearer \(token)' http://127.0.0.1:\(port)\(HookServer.installPath) | sh"
    }

    var sshConfigSnippet: String {
        "RemoteForward \(port) 127.0.0.1:\(port)"
    }

    static func remoteInstallScript(for installers: [HookInstaller]) -> String {
        var script = """
        #!/bin/sh
        set -e
        command -v python3 >/dev/null 2>&1 || { echo "Islet: python3 is required to update hook settings" >&2; exit 1; }
        install_hooks() {
          dir="$1"
          script="$dir/\(scriptName)"
          mkdir -p "$dir"
          (umask 077 && printf '%s\n' "$3" > "$script")
          chmod 700 "$script"
          python3 - "$dir/$2" "$script" "$4" <<'ISLET_SETTINGS'
        import json, os, sys
        path, script, entries = sys.argv[1], sys.argv[2], json.loads(sys.argv[3].replace("\(scriptPlaceholder)", sys.argv[2]))
        settings = {}
        if os.path.exists(path):
            with open(path) as f:
                text = f.read()
            settings = json.loads(text) if text.strip() else {}
        if not isinstance(settings, dict):
            sys.exit(f"Islet: {path} is not a JSON object")
        hooks = settings.setdefault("hooks", {})
        for event, entry in entries.items():
            groups = [g for g in hooks.get(event, []) if not any("\(scriptName)" in h.get("command", "") for h in g.get("hooks", []))]
            groups.append({"hooks": [entry]})
            hooks[event] = groups
        with open(path, "w") as f:
            json.dump(settings, f, indent=2, sort_keys=True, ensure_ascii=False)
            f.write("\\n")
        ISLET_SETTINGS
          echo "Islet hooks installed in $dir."
        }

        """
        for installer in installers {
            let entries = installer.events.reduce(into: [String: Any]()) { $0[$1] = hookEntry(for: $1, script: scriptPlaceholder) }
            let data = try! JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys, .withoutEscapingSlashes])
            let arguments = "\"\(installer.remoteDirectoryExpression)\" \(installer.settingsFileName) \(shellQuoted(installer.script.trimmingCharacters(in: .newlines))) \(shellQuoted(String(decoding: data, as: UTF8.self)))"
            switch installer.agent {
            case .claudeCode:
                script += "install_hooks \(arguments)\n"
            case .codex:
                script += "[ -d \"\(installer.remoteDirectoryExpression)\" ] && install_hooks \(arguments)\n"
            }
        }
        script += "echo \"Restart agent sessions on this machine to report them to Islet.\"\n"
        return script
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    var isInstalled: Bool {
        hasAllHooks && isScriptCurrent
    }

    var needsUpgrade: Bool {
        hasAnyHooks && !isInstalled
    }

    private var hasAnyHooks: Bool {
        guard let settings = try? readSettings(), let hooks = settings["hooks"] as? [String: Any] else { return false }
        return events.contains { !Self.isletHooks(in: hooks[$0]).isEmpty }
    }

    private var hasAllHooks: Bool {
        guard let settings = try? readSettings(), let hooks = settings["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { event in
            Self.isletHooks(in: hooks[event]).contains { NSDictionary(dictionary: $0).isEqual(to: Self.hookEntry(for: event, script: scriptURL.path)) }
        }
    }

    private var isScriptCurrent: Bool {
        (try? String(contentsOf: scriptURL, encoding: .utf8)) == script
    }

    func install() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: scriptURL.path, contents: Data(script.utf8), attributes: [.posixPermissions: 0o700]) else {
            throw CocoaError(.fileWriteUnknown)
        }

        var settings = try readSettings() ?? [:]
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var groups = Self.withoutIsletHooks(hooks[event])
            groups.append(["hooks": [Self.hookEntry(for: event, script: scriptURL.path)]])
            hooks[event] = groups
        }
        settings["hooks"] = hooks
        try writeSettings(settings)
    }

    func uninstall() throws {
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
        let quoted = "'" + script.replacingOccurrences(of: "'", with: "'\\''") + "'"
        switch event {
        case "PermissionRequest":
            let seconds = Int(HookServer.replyTimeout.components.seconds)
            return ["type": "command", "command": "\(quoted) \(seconds)", "timeout": seconds + 5]
        case "SessionEnd":
            return ["type": "command", "command": "\(quoted) 2", "timeout": 3]
        default:
            return ["type": "command", "command": quoted, "timeout": 10]
        }
    }

    private static func isletHooks(in groups: Any?) -> [[String: Any]] {
        (groups as? [[String: Any]] ?? []).flatMap { group in
            (group["hooks"] as? [[String: Any]] ?? []).filter { ($0["command"] as? String)?.contains(scriptName) == true }
        }
    }

    private static func withoutIsletHooks(_ groups: Any?) -> [[String: Any]] {
        (groups as? [[String: Any]] ?? []).filter { group in
            let commands = (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
            return !commands.contains { $0.contains(scriptName) }
        }
    }

    struct UnreadableSettings: Error, LocalizedError {
        let path: String
        var errorDescription: String? { "\(path) is not a JSON object" }
    }

    private func readSettings() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return nil }
        let data = try Data(contentsOf: settingsURL)
        if String(decoding: data, as: UTF8.self).allSatisfy(\.isWhitespace) { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw UnreadableSettings(path: settingsDescription) }
        return object
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
    }
}
