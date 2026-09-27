import Foundation
import Testing
import IsletCore

@MainActor
struct AppSettingsTests {
    @Test func defaultsWithoutStore() {
        let settings = AppSettings()
        #expect(settings.animation == .default)
        #expect(settings.switchesToDropTargetOnDrag)
        #expect(!settings.drawsIdleNotchShape)
        #expect(settings.notchSize == .medium)
        #expect(settings.displayPlacement == .builtIn)
        #expect(settings.showsMenuBarIcon)
        #expect(settings.pillSelection == .lastViewed)
    }

    @Test func persistsNotchSizeDisplayMenuBarIconAndPillSelection() {
        let suite = "AppSettingsTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: URL.libraryDirectory.appending(path: "Preferences/\(suite).plist"))
        }

        let first = AppSettings(defaults: defaults)
        first.notchSize = .large
        first.displayPlacement = .named("Studio Display")
        first.showsMenuBarIcon = false
        first.pillSelection = .latestActivity

        let second = AppSettings(defaults: defaults)
        #expect(second.notchSize == .large)
        #expect(second.displayPlacement == .named("Studio Display"))
        #expect(!second.showsMenuBarIcon)
        #expect(second.pillSelection == .latestActivity)

        second.resetAll()
        let third = AppSettings(defaults: defaults)
        #expect(third.notchSize == .medium)
        #expect(third.displayPlacement == .builtIn)
        #expect(third.showsMenuBarIcon)
        #expect(third.pillSelection == .lastViewed)
    }

    @Test func notchSizeScalesTheControllerGeometry() {
        let settings = AppSettings()
        let screen = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchSize: CGSize(width: 196, height: 32), hasHardwareNotch: true)
        let controller = NotchController(settings: settings, geometry: screen)
        let base = controller.geometry.contentSize(for: CGSize(width: 400, height: 200))

        settings.notchSize = .large
        #expect(controller.geometry.contentScale == 1.2)
        #expect(controller.geometry.contentSize(for: CGSize(width: 400, height: 200)) == CGSize(width: base.width * 1.2, height: base.height * 1.2))
        #expect(controller.geometry.panelSize == controller.screenGeometry.panelSize)
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
        first.drawsIdleNotchShape = true

        let second = AppSettings(defaults: defaults)
        #expect(second.animation.curve == .spring(dampingFraction: 0.55))
        #expect(second.animation.expandDelay == .milliseconds(90))
        #expect(!second.switchesToDropTargetOnDrag)
        #expect(second.drawsIdleNotchShape)

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

    @Test func incompatibleStoredDataFallsBackToDefaults() {
        let suite = "AppSettingsTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: URL.libraryDirectory.appending(path: "Preferences/\(suite).plist"))
        }
        defaults.set("garbage", forKey: "islet.settings.animation")
        defaults.set(Data("{\"expandDuration\": 0.9, \"curve\": {\"wobble\": {}}}".utf8), forKey: "islet.settings.switchesToDropTargetOnDrag")

        let settings = AppSettings(defaults: defaults)
        #expect(settings.animation == .default)
        #expect(settings.switchesToDropTargetOnDrag)
    }

    @Test func partialAnimationDataKeepsKnownFieldsAndDefaultsTheRest() throws {
        let data = Data("{\"expandDuration\": 0.9, \"curve\": {\"wobble\": {}}}".utf8)
        let animation = try JSONDecoder().decode(NotchAnimation.self, from: data)

        #expect(animation.expandDuration == 0.9)
        #expect(animation.curve == NotchAnimation.default.curve)
        #expect(animation.collapseDelay == NotchAnimation.default.collapseDelay)
    }

    @Test func durationMillisecondsRoundTrip() {
        #expect(Duration.milliseconds(250).milliseconds == 250)
        #expect(Duration.seconds(1.5).milliseconds == 1500)
        #expect(Duration.zero.milliseconds == 0)
    }
}
