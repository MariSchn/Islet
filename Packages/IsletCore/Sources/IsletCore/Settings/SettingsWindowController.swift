import AppKit
import SwiftUI

@MainActor
public final class SettingsWindowController {
    private let window: NSWindow

    public init(settings: AppSettings, registry: PluginRegistry) {
        let hosting = NSHostingController(rootView: SettingsView(settings: settings, registry: registry))
        window = NSWindow(contentViewController: hosting)
        window.title = "Islet Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("IsletSettings")
        window.center()
    }

    public func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
