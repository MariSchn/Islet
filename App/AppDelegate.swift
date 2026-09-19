import AppKit
import HelloPlugin
import IsletCore
import ShelfPlugin
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings(defaults: .standard)
    let registry = PluginRegistry(
        storageRoot: URL.applicationSupportDirectory.appending(path: "Islet/Plugins", directoryHint: .isDirectory)
    )
    private(set) lazy var notchController = NotchController(settings: settings)
    private var panel: NotchPanel?
    private lazy var settingsWindow = SettingsWindowController(settings: settings, registry: registry)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = NotchPanel(controller: notchController) { [registry, weak self] in
            NotchHostView(registry: registry) { self?.showSettings() }
        }
        panel.show()
        self.panel = panel

        notchController.attach(registry)
        Task { @MainActor in
            await registerBuiltInPlugins()
        }
    }

    func showSettings() {
        settingsWindow.show()
    }

    private func registerBuiltInPlugins() async {
        do {
            try await registry.register(manifest: ShelfPlugin.manifest) { ShelfPlugin(context: $0) }
            try await registry.register(manifest: HelloPlugin.manifest) { HelloPlugin(context: $0) }
        } catch {
            NSLog("Failed to register built-in plugin: \(error)")
        }
    }
}
