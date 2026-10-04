import Foundation

struct HookInstaller: Sendable {
    static let scriptName = "islet-hook.sh"
    static let antigravityHookName = "islet"
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

    init(agent: AgentSession.Agent, home: URL, port: UInt16, token: String) {
        self.init(agent: agent, directory: home.appending(path: agent.hookPath, directoryHint: .isDirectory), port: port, token: token)
    }

    var events: [String] {
        switch agent {
        case .claudeCode: ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest", "PermissionDenied", "Notification", "Stop", "StopFailure"]
        case .codex: ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop"]
        case .antigravity: ["PreInvocation", "PostToolUse", "Stop"]
        }
    }

    var settingsFileName: String {
        switch agent {
        case .claudeCode: "settings.json"
        case .codex, .antigravity: "hooks.json"
        }
    }

    private var remoteDirectoryExpression: String {
        switch agent {
        case .claudeCode: "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
        case .codex: "${CODEX_HOME:-$HOME/.codex}"
        case .antigravity: "$HOME/.gemini/config"
        }
    }

    var scriptURL: URL { directory.appending(path: Self.scriptName) }
    var settingsURL: URL { directory.appending(path: settingsFileName) }
    private var settingsFile: SettingsFile { SettingsFile(url: settingsURL) }

    var script: String {
        """
        #!/bin/sh
        timeout="${1:-5}"
        event="$2"
        payload=$(cat)
        \(agent == .antigravity ? "printf '{}\\n'\n" : "")title=""
        transcript=""
        name="${event:-$(printf '%s' "$payload" | sed -n 's/.*"hook_event_name":"\\([A-Za-z]*\\)".*/\\1/p')}"
        case "$name" in
          SessionStart|UserPromptSubmit|Stop|StopFailure) transcript=$(printf '%s' "$payload" | sed -n 's/.*"transcript_path":"\\([^"]*\\)".*/\\1/p') ;;
        esac
        if [ -n "$transcript" ] && [ -f "$transcript" ]; then
          titles=$(grep -oE '"(customTitle|aiTitle)":"([^"\\\\]|\\\\.)*"' "$transcript" 2>/dev/null)
          title=$(printf '%s\\n' "$titles" | grep '^"customTitle"' | tail -n 1)
          [ -n "$title" ] || title=$(printf '%s\\n' "$titles" | grep '^"aiTitle"' | tail -n 1)
          title=$(printf '%s' "$title" | sed 's/^"[A-Za-z]*":"//; s/"$//; s/\\\\"/"/g; s/\\\\\\\\/\\\\/g')
        fi
        if [ -n "$transcript" ] && [ -z "$title" ] && [ -f "${0%/*}/session_index.jsonl" ]; then
          session=$(printf '%s' "$payload" | sed -n 's/.*"session_id":"\\([^"]*\\)".*/\\1/p')
          title=$(grep -F "\\"id\\":\\"$session\\"" "${0%/*}/session_index.jsonl" 2>/dev/null | tail -n 1 | sed -nE 's/.*"thread_name":"(([^"\\\\]|\\\\.)*)".*/\\1/p' | sed 's/\\\\"/"/g; s/\\\\\\\\/\\\\/g')
        fi
        branch=""
        if [ -n "$transcript" ] && [ -f "$transcript" ]; then
          branch=$(head -n 1 "$transcript" | sed -nE 's/.*"git":\\{[^}]*"branch":"([^"]*)".*/\\1/p')
        fi
        \(agent == .antigravity ? Self.antigravityBranchLines : "")terminal="${__CFBundleIdentifier:-$TERM_PROGRAM}"
        tty=""
        agent_pid=""
        pid=$$
        case "$name" in
          PreToolUse|PostToolUse|PostToolUseFailure|PermissionDenied|SessionEnd) ;;
          *)
            set -f
            while [ "$pid" -gt 1 ]; do
              set -- $(ps -o ppid=,tty=,comm= -p "$pid" 2>/dev/null)
              [ -n "$1" ] || break
              case "$2" in ""|"?"|"??") ;; *) tty="/dev/$2" ;; esac
              if [ -z "$agent_pid" ]; then
                case "${3##*/}" in claude|claude-*|node|bun|codex|codex-*|agy|[0-9]*.[0-9]*.[0-9]*) agent_pid=$pid ;; esac
              fi
              if [ -z "$terminal" ] && [ "$(uname)" = Darwin ]; then
                vars=$(ps -E -o command= -p "$pid" 2>/dev/null | tr ' ' '\n')
                terminal=$(printf '%s\n' "$vars" | sed -n 's/^__CFBundleIdentifier=//p' | head -n 1)
                [ -n "$terminal" ] || terminal=$(printf '%s\n' "$vars" | sed -n 's/^TERM_PROGRAM=//p' | head -n 1)
              fi
              pid=$1
            done
            ;;
        esac
        case "$terminal" in vscode) case "$VSCODE_GIT_ASKPASS_MAIN" in *[Cc]ursor*) terminal=cursor ;; esac ;; esac
        body=$(mktemp) || exit 0
        request=""
        trap '[ -n "$request" ] && kill "$request" 2>/dev/null; rm -f "$body"; exit 0' HUP INT TERM
        printf '%s' "$payload" > "$body"
        curl -sf --connect-timeout 1 -m "$timeout" -K - -X POST "http://127.0.0.1:\(port)\(HookServer.hookPath)" \\
          -H "Content-Type: application/json" \\
          -H "Expect:" \\
          -H "X-Islet-Agent: \(agent.rawValue)" \\
          -H "X-Islet-Event: $event" \\
          -H "X-Islet-Host: $(hostname -s 2>/dev/null || hostname)" \\
          -H "X-Islet-Terminal: $terminal" \\
          -H "X-Islet-TTY: $tty" \\
          -H "X-Islet-PID: $agent_pid" \\
          -H "X-Islet-Tmux: $TMUX" \\
          -H "X-Islet-Tmux-Pane: $TMUX_PANE" \\
          -H "X-Islet-Title: $title" \\
          -H "X-Islet-Branch: $branch" \\
          --data-binary "@$body" \(agent == .antigravity ? ">/dev/null " : "")2>/dev/null <<'ISLET_CONFIG' &
        header = "Authorization: Bearer \(token)"
        ISLET_CONFIG
        request=$!
        wait "$request"
        request=""
        rm -f "$body"
        exit 0

        """
    }

    private static let antigravityBranchLines = """
        branch=""
        case "$event" in
          PreInvocation|Stop)
            workspace=$(printf '%s' "$payload" | sed -n 's/.*"workspacePaths":\\["\\([^"]*\\)".*/\\1/p')
            [ -n "$workspace" ] && branch=$(git -C "$workspace" branch --show-current 2>/dev/null) ;;
        esac

        """

    func remoteInstallCommand(code: String) -> String {
        "curl -sf -H 'Authorization: Bearer \(code)' http://127.0.0.1:\(port)\(HookServer.installPath) | sh"
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
            let arguments = "\"\(installer.remoteDirectoryExpression)\" \(installer.settingsFileName) \(installer.script.trimmingCharacters(in: .newlines).shellQuoted) \(String(decoding: data, as: UTF8.self).shellQuoted)"
            let condition = installer.agent == .claudeCode ? "" : "[ -d \"\(installer.remoteDirectoryExpression)\" ] && "
            script += "\(condition)install_hooks \(arguments)\n"
        }
        script += "echo \"Restart agent sessions on this machine to report them to Islet.\"\n"
        return script
    }

    var isInstalled: Bool {
        hasAllHooks && isScriptCurrent
    }

    var needsUpgrade: Bool {
        hasAnyHooks && !isInstalled
    }

    private var hasAnyHooks: Bool {
        if agent == .antigravity {
            return (try? settingsFile.read())??[Self.antigravityHookName] != nil
        }
        guard let settings = try? settingsFile.read(), let hooks = settings["hooks"] as? [String: Any] else { return false }
        return events.contains { !Self.isletHooks(in: hooks[$0]).isEmpty }
    }

    private var hasAllHooks: Bool {
        if agent == .antigravity {
            guard let hook = (try? settingsFile.read())??[Self.antigravityHookName] as? [String: Any] else { return false }
            return NSDictionary(dictionary: hook).isEqual(to: antigravityHook)
        }
        guard let settings = try? settingsFile.read(), let hooks = settings["hooks"] as? [String: Any] else { return false }
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

        var settings = try settingsFile.read() ?? [:]
        if agent == .antigravity {
            settings[Self.antigravityHookName] = antigravityHook
            try settingsFile.write(settings)
            return
        }
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var groups = Self.withoutIsletHooks(hooks[event])
            groups.append(["hooks": [Self.hookEntry(for: event, script: scriptURL.path)]])
            hooks[event] = groups
        }
        settings["hooks"] = hooks
        try settingsFile.write(settings)
    }

    func uninstall() throws {
        if agent == .antigravity {
            if var settings = try settingsFile.read(), settings[Self.antigravityHookName] != nil {
                settings[Self.antigravityHookName] = nil
                try settingsFile.write(settings)
            }
        } else if var settings = try settingsFile.read(), var hooks = settings["hooks"] as? [String: Any] {
            for event in hooks.keys {
                let groups = Self.withoutIsletHooks(hooks[event])
                hooks[event] = groups.isEmpty ? nil : groups
            }
            settings["hooks"] = hooks.isEmpty ? nil : hooks
            try settingsFile.write(settings)
        }
        try? FileManager.default.removeItem(at: scriptURL)
    }

    static func hookEntry(for event: String, script: String) -> [String: Any] {
        let quoted = script.shellQuoted
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

    var antigravityHook: [String: Any] {
        let quoted = scriptURL.path.shellQuoted
        return events.reduce(into: [String: Any]()) { hook, event in
            let entry: [String: Any] = ["type": "command", "command": "\(quoted) 2 \(event)", "timeout": 5]
            hook[event] = event == "PostToolUse" ? [["matcher": "*", "hooks": [entry]]] : [entry]
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
}

extension String {
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
