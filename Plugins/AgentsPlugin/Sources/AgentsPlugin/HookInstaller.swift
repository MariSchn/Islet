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
        if [ -r /proc/net/tcp ]; then
          owner=$(awk '($2 == "0100007F:\(hexPort)" || $2 == "00000000:\(hexPort)") && $4 == "0A" { print $8; exit }' /proc/net/tcp)
          [ "$owner" = "$(id -u)" ] || exit 0
        fi
        case "$name" in
          PermissionRequest)
            if [ "$(uname)" = Darwin ]; then
              owner=$(PATH="$PATH:/usr/sbin" lsof -nP -a -iTCP@127.0.0.1:\(port) -sTCP:LISTEN -Fu 2>/dev/null | sed -n 's/^u//p' | head -n 1)
              [ "$owner" = "$(id -u)" ] || exit 0
            fi
            ;;
          *) exec >/dev/null ;;
        esac
        request=""
        trap '[ -n "$request" ] && kill "$request" 2>/dev/null; exit 0' HUP INT TERM
        printf '%s' "$payload" | curl -sf --connect-timeout 1 -m "$timeout" -K /dev/fd/3 -X POST "http://127.0.0.1:\(port)\(HookServer.hookPath)" \\
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
          --data-binary @- \(agent == .antigravity ? ">/dev/null " : "")2>/dev/null 3<<'ISLET_CONFIG' &
        header = "Authorization: Bearer \(token)"
        ISLET_CONFIG
        request=$!
        wait "$request"
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

    private var hexPort: String {
        String(format: "%04X", port)
    }

    func remoteInstallCommand(code: String, scriptHash: String) -> String {
        let verify = #"import hashlib,subprocess,sys; s=sys.stdin.buffer.read(); sys.exit("Islet: could not reach Islet, is the SSH tunnel up?" if not s else "Islet: this install command expired or was replaced, copy a new one in Islet" if s.startswith(b"{") else "Islet: unexpected install script, not running it" if hashlib.sha256(s).hexdigest()!="\#(scriptHash)" else subprocess.run(["sh"],input=s).returncode)"#
        return "printf 'header = \"Authorization: Bearer \(code)\"\\n' | curl -s -K - http://127.0.0.1:\(port)\(HookServer.installPath) | python3 -c '\(verify)'"
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
        import json, os, sys, tempfile
        path, script, entries = os.path.realpath(sys.argv[1]), sys.argv[2], json.loads(sys.argv[3])
        settings = {}
        if os.path.exists(path):
            with open(path, encoding="utf-8") as f:
                text = f.read()
            settings = json.loads(text) if text.strip() else {}
        if not isinstance(settings, dict) or not isinstance(settings.setdefault("hooks", {}), dict):
            sys.exit(f"Islet: {path} has an unexpected format, not changing it")
        hooks = settings["hooks"]
        def islet(hook):
            return isinstance(hook, dict) and "\(scriptName)" in str(hook.get("command", ""))
        for event, entry in entries.items():
            entry["command"] = entry["command"].replace("'\(scriptPlaceholder)'", "'" + script.replace("'", "'\\\\''") + "'")
            groups = []
            for group in hooks.get(event) if isinstance(hooks.get(event), list) else []:
                if isinstance(group, dict) and isinstance(group.get("hooks"), list) and any(islet(h) for h in group["hooks"]):
                    kept = [h for h in group["hooks"] if not islet(h)]
                    if not kept:
                        continue
                    group = dict(group, hooks=kept)
                groups.append(group)
            groups.append({"hooks": [entry]})
            hooks[event] = groups
        fd, temp = tempfile.mkstemp(prefix=".islet-", dir=os.path.dirname(path))
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump(settings, f, indent=2, sort_keys=True, ensure_ascii=False)
                f.write("\\n")
            if os.path.exists(path):
                os.chmod(temp, os.stat(path).st_mode & 0o7777)
            os.replace(temp, path)
        except BaseException:
            os.unlink(temp)
            raise
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
            for (event, value) in hooks {
                guard let groups = value as? [Any], !Self.isletHooks(in: groups).isEmpty else { continue }
                let kept = Self.withoutIsletHooks(groups)
                hooks[event] = kept.isEmpty ? nil : kept
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

    private static func isIsletHook(_ hook: Any) -> Bool {
        ((hook as? [String: Any])?["command"] as? String)?.contains(scriptName) == true
    }

    private static func isletHooks(in groups: Any?) -> [[String: Any]] {
        (groups as? [Any] ?? []).flatMap { group in
            ((group as? [String: Any])?["hooks"] as? [Any] ?? []).filter(isIsletHook).compactMap { $0 as? [String: Any] }
        }
    }

    private static func withoutIsletHooks(_ groups: Any?) -> [Any] {
        (groups as? [Any] ?? []).compactMap { element in
            guard var group = element as? [String: Any], let hooks = group["hooks"] as? [Any], hooks.contains(where: isIsletHook) else { return element }
            let kept = hooks.filter { !isIsletHook($0) }
            guard !kept.isEmpty else { return nil }
            group["hooks"] = kept
            return group
        }
    }
}

extension String {
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
