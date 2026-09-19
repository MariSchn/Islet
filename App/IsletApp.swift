import IsletCore
import SwiftUI

@main
struct IsletApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra("Islet", systemImage: "circle.hexagongrid") {
            PluginMenu(registry: appDelegate.registry)
            Divider()
            Button("Quit Islet") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

private struct PluginMenu: View {
    let registry: PluginRegistry

    var body: some View {
        ForEach(registry.entries) { entry in
            Toggle(entry.manifest.displayName, isOn: Binding(
                get: { registry.isEnabled(entry.id) },
                set: { enabled in Task { await registry.setEnabled(enabled, for: entry.id) } }
            ))
        }
    }
}
