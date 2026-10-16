import AppKit

@MainActor
struct InstalledTerminal {
    let app: TerminalApp
    let url: URL
    let name: String
    let icon: NSImage

    private static var installed: [TerminalApp: InstalledTerminal?] = [:]
    private static let scripts = TerminalScriptRunner()
    private static let commands = TerminalCommandRunner()
    private static let tmuxFallbacks = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
    private static let scriptTimeout = 3

    static func lookup(_ app: TerminalApp) -> InstalledTerminal? {
        if let cached = installed[app] { return cached }
        let terminal = InstalledTerminal(app)
        installed[app] = terminal
        return terminal
    }

    init?(_ app: TerminalApp) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) else { return nil }
        self.app = app
        self.url = url
        name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        icon = NSWorkspace.shared.icon(forFile: url.path)
    }

    func activate(tty: String?, cwd: String?) {
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).first else {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return
        }
        running.activate()
        switch app.targeting {
        case .terminalTab:
            if let tty { runScript(Self.terminalTabScript(tty: tty)) }
        case .iTermSession:
            if let tty { runScript(Self.iTermSessionScript(tty: tty)) }
        case .editorFolder:
            if let cwd {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.open([URL(filePath: cwd)], withApplicationAt: url, configuration: configuration)
            }
        case .wezTermPane:
            if let tty {
                let binary = url.appending(path: "Contents/MacOS/wezterm").path
                Task { await Self.focusWezTermPane(binary: binary, tty: tty) }
            }
        case .application:
            break
        }
    }

    static func showTmuxPane(_ location: TmuxLocation) async -> Bool {
        guard let tmux = tmuxBinary(for: location) else { return false }
        let base = ["-S", location.socket]
        guard let session = await commands.run(tmux, base + ["display-message", "-p", "-t", location.pane, "#{session_name}"])?.trimmingCharacters(in: .whitespacesAndNewlines),
              let listing = await commands.run(tmux, base + ["list-clients", "-F", TmuxClient.listFormat]),
              let client = TmuxClient.choose(from: TmuxClient.parse(listing), session: session)
        else { return false }
        for command in [["switch-client", "-c", client.tty, "-t", location.pane], ["select-window", "-t", location.pane], ["select-pane", "-t", location.pane]] {
            _ = await commands.run(tmux, base + command)
        }
        guard let host = hostApplication(of: client.pid) else { return false }
        host.activate()
        if let identifier = host.bundleIdentifier, HookEvent.isSafeIdentifier(client.tty) {
            switch TerminalApp(identifier: identifier)?.targeting {
            case .terminalTab: Task { await scripts.run(terminalTabScript(tty: client.tty)) }
            case .iTermSession: Task { await scripts.run(iTermSessionScript(tty: client.tty)) }
            default: break
            }
        }
        return true
    }

    private static func tmuxBinary(for location: TmuxLocation) -> String? {
        if let path = ProcessTree.executablePath(of: location.serverPID), (path as NSString).lastPathComponent == "tmux", FileManager.default.isExecutableFile(atPath: path) { return path }
        return tmuxFallbacks.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func hostApplication(of pid: Int32) -> NSRunningApplication? {
        for candidate in [pid] + ProcessTree.ancestors(of: pid) {
            if let app = NSRunningApplication(processIdentifier: candidate) { return app }
        }
        return nil
    }

    private static func focusWezTermPane(binary: String, tty: String) async {
        guard let listing = await commands.run(binary, ["cli", "list", "--format", "json"]),
              let pane = WezTermPanes.paneID(in: Data(listing.utf8), tty: tty)
        else { return }
        _ = await commands.run(binary, ["cli", "activate-pane", "--pane-id", String(pane)])
    }

    private func runScript(_ source: String) {
        Task { await Self.scripts.run(source) }
    }

    static func terminalTabScript(tty: String) -> String {
        """
        with timeout of \(scriptTimeout) seconds
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected tab of w to t
                            set frontmost of w to true
                            activate
                            return
                        end if
                    end repeat
                end repeat
                activate
            end tell
        end timeout
        """
    }

    static func iTermSessionScript(tty: String) -> String {
        """
        with timeout of \(scriptTimeout) seconds
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                tell w to select
                                tell t to select
                                tell s to select
                                activate
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
                activate
            end tell
        end timeout
        """
    }
}

private actor TerminalScriptRunner {
    func run(_ source: String) {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }
}
