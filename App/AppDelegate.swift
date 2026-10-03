import AgentsPlugin
import AppKit
import HelloPlugin
import IsletCore
import IsletHost
import MediaPlugin
import os
import ScriptsPlugin
import ShelfPlugin

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let builtInPlugins: [any IsletPlugin.Type] = [
        ShelfPlugin.self,
        MediaPlugin.self,
        AgentsPlugin.self,
        ScriptsPlugin.self,
    ] + examplePlugins
    #if DEBUG
    private static let examplePlugins: [any IsletPlugin.Type] = [HelloPlugin.self]
    #else
    private static let examplePlugins: [any IsletPlugin.Type] = []
    #endif
    private static let terminationTimeout: Duration = .seconds(2)
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Islet", category: "app")

    let settings = AppSettings(defaults: .standard)
    let registry = PluginRegistry(
        storageRoot: URL.applicationSupportDirectory.appending(path: "Islet/Plugins", directoryHint: .isDirectory)
    )
    private(set) lazy var displays = NotchDisplayManager(settings: settings) { [unowned self] display in
        makePanel(for: display)
    }
    private var statusItem: NSStatusItem?
    private var registration: Task<Void, Never>?
    private lazy var settingsWindow = SettingsWindowController(settings: settings, registry: registry)

    func applicationDidFinishLaunching(_ notification: Notification) {
        displays.start()
        observeMenuBarIconSetting()
        registration = Task { @MainActor in
            await registerBuiltInPlugins()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        var replied = false
        let reply = {
            guard !replied else { return }
            replied = true
            sender.reply(toApplicationShouldTerminate: true)
        }
        Task { @MainActor [registry, registration] in
            await registration?.value
            await registry.deactivateAll()
            reply()
        }
        Task { @MainActor in
            try? await Task.sleep(for: Self.terminationTimeout)
            reply()
        }
        return .terminateLater
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
        } onChange: { [weak self] in
            Task { @MainActor in
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
        for plugin in Self.builtInPlugins {
            do {
                try await registry.register(plugin)
            } catch {
                Self.logger.error("Failed to register \(plugin.manifest.id, privacy: .public): \(error, privacy: .public)")
            }
        }
    }
}
