import AgentsPlugin
import AppKit
import HelloPlugin
import IsletCore
import MediaPlugin
import ShelfPlugin

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings(defaults: .standard)
    let registry = PluginRegistry(
        storageRoot: URL.applicationSupportDirectory.appending(path: "Islet/Plugins", directoryHint: .isDirectory)
    )
    private(set) lazy var displays = NotchDisplayManager(settings: settings) { [unowned self] display in
        makePanel(for: display)
    }
    private var statusItem: NSStatusItem?
    private lazy var settingsWindow = SettingsWindowController(settings: settings, registry: registry)

    func applicationDidFinishLaunching(_ notification: Notification) {
        displays.start()
        observeMenuBarIconSetting()
        Task { @MainActor in
            await registerBuiltInPlugins()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func showSettings() {
        settingsWindow.show()
    }

    private func makePanel(for display: NotchDisplay) -> NotchPanel {
        let controller = NotchController(settings: settings)
        controller.attach(registry)
        return NotchPanel(display: display, controller: controller) { [registry, weak self] in
            NotchHostView(controller: controller, registry: registry) { self?.showSettings() }
        }
    }

    private func observeMenuBarIconSetting() {
        withObservationTracking {
            updateStatusItem(visible: settings.showsMenuBarIcon)
        } onChange: {
            Task { @MainActor [weak self] in
                self?.observeMenuBarIconSetting()
            }
        }
    }

    private func updateStatusItem(visible: Bool) {
        if visible {
            if statusItem == nil {
                statusItem = makeStatusItem()
            }
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "circle.hexagongrid", accessibilityDescription: "Islet")
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Islet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        return item
    }

    @objc private func openSettings() {
        showSettings()
    }

    private func registerBuiltInPlugins() async {
        do {
            try await registry.register(manifest: ShelfPlugin.manifest) { ShelfPlugin(context: $0) }
            try await registry.register(manifest: MediaPlugin.manifest) { MediaPlugin(context: $0) }
            try await registry.register(manifest: AgentsPlugin.manifest) { AgentsPlugin(context: $0) }
            try await registry.register(manifest: HelloPlugin.manifest) { HelloPlugin(context: $0) }
        } catch {
            NSLog("Failed to register built-in plugin: \(error)")
        }
    }
}
