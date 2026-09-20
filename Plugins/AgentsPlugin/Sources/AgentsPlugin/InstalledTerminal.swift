import AppKit

@MainActor
struct InstalledTerminal {
    let app: TerminalApp
    let url: URL
    let name: String
    let icon: NSImage

    private static var installed: [TerminalApp: InstalledTerminal] = [:]

    static func lookup(_ app: TerminalApp) -> InstalledTerminal? {
        if let cached = installed[app] { return cached }
        guard let terminal = InstalledTerminal(app) else { return nil }
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
        case .application:
            break
        }
    }

    private func runScript(_ source: String) {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }

    private static func terminalTabScript(tty: String) -> String {
        """
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
        """
    }

    private static func iTermSessionScript(tty: String) -> String {
        """
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
        """
    }
}
