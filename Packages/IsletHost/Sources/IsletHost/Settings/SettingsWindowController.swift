import AppKit
import IsletCore
import SwiftUI

@MainActor
public final class SettingsWindowController {
    private let window: NSWindow

    public init(settings: AppSettings, registry: PluginRegistry) {
        let hosting = NSHostingController(rootView: SettingsView(settings: settings, registry: registry))
        hosting.sizingOptions = [.minSize]
        window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Islet Settings", bundle: .module)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.styleMask.insert(.fullSizeContentView)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 820, height: 560))
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
