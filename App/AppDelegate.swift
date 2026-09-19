import AppKit
import HelloPlugin
import IsletCore
import ShelfPlugin
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let registry = PluginRegistry(
        storageRoot: URL.applicationSupportDirectory.appending(path: "Islet/Plugins", directoryHint: .isDirectory)
    )
    let notchController = NotchController()
    private var panel: NotchPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = NotchPanel(controller: notchController) { [registry] in
            NotchHostView(registry: registry)
        }
        panel.show()
        self.panel = panel

        notchController.attach(registry)
        Task { @MainActor in
            await registerBuiltInPlugins()
        }
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
