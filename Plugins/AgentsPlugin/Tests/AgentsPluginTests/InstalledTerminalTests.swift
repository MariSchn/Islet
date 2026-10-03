import AppKit
import Testing
@testable import AgentsPlugin

@MainActor
struct InstalledTerminalTests {
    @Test(.enabled(if: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") != nil, "Compiling needs Terminal's scripting dictionary"))
    func terminalScriptCompiles() {
        #expect(compileError(InstalledTerminal.terminalTabScript(tty: "/dev/ttys003")) == nil)
    }

    @Test(.enabled(if: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") != nil, "Compiling needs iTerm2's scripting dictionary"))
    func iTermScriptCompiles() {
        #expect(compileError(InstalledTerminal.iTermSessionScript(tty: "/dev/ttys003")) == nil)
    }

    private func compileError(_ source: String) -> NSDictionary? {
        guard let script = NSAppleScript(source: source) else { return [:] }
        var error: NSDictionary?
        return script.compileAndReturnError(&error) ? nil : (error ?? [:])
    }
}
