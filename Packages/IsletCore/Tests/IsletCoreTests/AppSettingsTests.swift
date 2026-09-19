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
