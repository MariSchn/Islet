import Foundation
import IsletCore
import Testing
@testable import SystemMonitorPlugin

@MainActor
struct SystemMonitorPluginTests {
    @Test func registersDerivesItsSizeAndSavesRowSettings() async throws {
        let suite = "SystemMonitorPluginTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        defer { try? FileManager.default.removeItem(at: root) }

        let registry = PluginRegistry(storageRoot: root, userDefaults: defaults)
        let entry = try await registry.register(SystemMonitorPlugin.self)
        let plugin = try #require(entry.plugin as? SystemMonitorPlugin)
        #expect(entry.state.isActive)
        #expect(plugin.monitor.isRunning)
        #expect(entry.context.pillStatus == nil)

        let deadline = ContinuousClock.now + .seconds(5)
        while plugin.monitor.sample == nil || entry.context.contentSize != SystemMonitorPlugin.contentSize(for: plugin.monitor.visibleRows) {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(defaults.object(forKey: "plugin.islet.system.showDisk") == nil)

        plugin.monitor.enabledRows.remove(.disk)
        while defaults.object(forKey: "plugin.islet.system.showDisk") as? Bool != false {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
        #expect(defaults.bool(forKey: "plugin.islet.system.showCPU"))
        while entry.context.contentSize != SystemMonitorPlugin.contentSize(for: plugin.monitor.visibleRows) {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
        #expect(!plugin.monitor.visibleRows.contains(.disk))

        await registry.setEnabled(false, for: SystemMonitorPlugin.manifest.id)
        #expect(!plugin.monitor.isRunning)
    }
}
