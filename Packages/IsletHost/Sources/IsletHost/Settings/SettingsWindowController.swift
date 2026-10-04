import AppKit
import IsletCore
import SwiftUI

@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let navigation: SettingsNavigation

    public init(settings: AppSettings, registry: PluginRegistry, info: AppInfo, updater: (any AppUpdater)?) {
        let navigation = SettingsNavigation()
        self.navigation = navigation
        let hosting = NSHostingController(rootView: SettingsView(settings: settings, registry: registry, navigation: navigation, info: info, updater: updater))
        hosting.sizingOptions = [.minSize]
        window = NSWindow(contentViewController: hosting)
        super.init()
        window.title = "Islet Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.styleMask.insert(.fullSizeContentView)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 820, height: 600))
        if !window.setFrameUsingName("IsletSettings") {
            window.center()
        }
        window.setFrameAutosaveName("IsletSettings")
    }

    public func show(_ pane: SettingsPane? = nil) {
        if let pane {
            navigation.pane = pane
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
