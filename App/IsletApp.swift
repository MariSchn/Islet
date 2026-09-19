import IsletCore
import SwiftUI

@main
struct IsletApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var registry = PluginRegistry(storageRoot: Self.storageRoot)

    private static var storageRoot: URL {
        URL.applicationSupportDirectory.appending(path: "Islet/Plugins", directoryHint: .isDirectory)
    }

    var body: some Scene {
        MenuBarExtra("Islet", systemImage: "circle.hexagongrid") {
            Button("Quit Islet") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
