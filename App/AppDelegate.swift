import AppKit
import IsletCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let notchController = NotchController(
        geometry: NotchGeometry(screen: NotchGeometry.preferredScreen() ?? NSScreen.screens[0])
    )
    private var panel: NotchPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = NotchPanel(controller: notchController) {
            Text("Islet")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
        }
        panel.show()
        self.panel = panel
    }
}
