import AppKit
import SwiftUI

@MainActor
public final class SettingsWindowController {
    private let window: NSWindow

    public init(settings: AppSettings, registry: PluginRegistry) {
        let hosting = NSHostingController(rootView: SettingsView(settings: settings, registry: registry))
        hosting.sizingOptions = [.minSize]
        window = NSWindow(contentViewController: hosting)
        window.title = "Islet Settings"
        window.isReleasedWhenClosed = false
        if !window.setFrameUsingName("IsletSettings") {
            window.center()
        }
        window.setFrameAutosaveName("IsletSettings")
    }

    public func show() {
        NSApp.activate()
        window.orderFrontRegardless()
        window.makeKey()
    }
}
