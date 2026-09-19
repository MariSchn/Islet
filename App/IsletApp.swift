import IsletCore
import SwiftUI

@main
struct IsletApp: App {
    @State private var registry = PluginRegistry(storageRoot: Self.storageRoot)

    private static var storageRoot: URL {
        URL.applicationSupportDirectory.appending(path: "Islet/Plugins", directoryHint: .isDirectory)
    }

    var body: some Scene {
        MenuBarExtra("Islet", systemImage: "circle.hexagongrid") {
            Text("\(registry.enabledEntries.count) plugins")
            Divider()
            Button("Quit Islet") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
