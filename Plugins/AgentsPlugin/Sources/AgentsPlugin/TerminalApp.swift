import Foundation

struct TerminalApp: Sendable, Equatable, Hashable, Codable {
    enum Targeting: Sendable {
        case terminalTab
        case iTermSession
        case editorFolder
        case wezTermPane
        case application
    }

    private static let programs = [
        "Apple_Terminal": "com.apple.Terminal",
        "iTerm.app": "com.googlecode.iterm2",
        "ghostty": "com.mitchellh.ghostty",
        "WarpTerminal": "dev.warp.Warp-Stable",
        "WezTerm": "com.github.wez.wezterm",
        "kitty": "net.kovidgoyal.kitty",
        "Alacritty": "org.alacritty",
        "Hyper": "co.zeit.hyper",
        "Tabby": "org.tabby",
        "vscode": "com.microsoft.VSCode",
        "cursor": "com.todesktop.230313mzl4w4u92",
    ]

    private static let editors: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium",
        "com.todesktop.230313mzl4w4u92",
    ]

    let bundleIdentifier: String

    init?(identifier: String) {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        bundleIdentifier = Self.programs[trimmed] ?? trimmed
    }

    var targeting: Targeting {
        switch bundleIdentifier {
        case "com.apple.Terminal": .terminalTab
        case "com.googlecode.iterm2": .iTermSession
        case "com.github.wez.wezterm": .wezTermPane
        case _ where Self.editors.contains(bundleIdentifier): .editorFolder
        default: .application
        }
    }
}
