import Foundation
import Testing
import IsletCore

@MainActor
struct AppSettingsTests {
    @Test func defaultsWithoutStore() {
        let settings = AppSettings()
        #expect(settings.animation == .default)
        #expect(settings.switchesToDropTargetOnDrag)
        #expect(!settings.showsIdleNotchOutline)
    }

    @Test func persistsAnimationAndDragBehavior() {
        let suite = "AppSettingsTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: URL.libraryDirectory.appending(path: "Preferences/\(suite).plist"))
        }

        let first = AppSettings(defaults: defaults)
        first.animation.curve = .spring(dampingFraction: 0.55)
        first.animation.expandDelay = .milliseconds(90)
        first.switchesToDropTargetOnDrag = false
        first.showsIdleNotchOutline = true

        let second = AppSettings(defaults: defaults)
        #expect(second.animation.curve == .spring(dampingFraction: 0.55))
        #expect(second.animation.expandDelay == .milliseconds(90))
        #expect(!second.switchesToDropTargetOnDrag)
        #expect(second.showsIdleNotchOutline)

        second.resetAnimation()
        #expect(AppSettings(defaults: defaults).animation == .default)
    }

    @Test func controllerReadsAndWritesThroughSettings() {
        let settings = AppSettings()
        let controller = NotchController(settings: settings)

        controller.animation.collapseDelay = .milliseconds(5)
        controller.switchesToDropTargetOnDrag = false

        #expect(settings.animation.collapseDelay == .milliseconds(5))
        #expect(!settings.switchesToDropTargetOnDrag)
    }
}
