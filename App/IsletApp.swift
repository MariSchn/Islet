import IsletCore
import SwiftUI

@main
struct IsletApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra("Islet", systemImage: "circle.hexagongrid") {
            Button("Quit Islet") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
