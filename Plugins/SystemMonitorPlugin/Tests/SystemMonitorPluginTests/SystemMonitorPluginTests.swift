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

    @Test func derivesThePillAndAnnouncesConditions() async throws {
        let suite = "SystemMonitorPluginTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        defer { try? FileManager.default.removeItem(at: root) }

        let registry = PluginRegistry(storageRoot: root, userDefaults: defaults)
        let entry = try await registry.register(SystemMonitorPlugin.self)
        let plugin = try #require(entry.plugin as? SystemMonitorPlugin)
        let monitor = plugin.monitor
        monitor.stop()
        defer { monitor.stop() }

        let deadline = ContinuousClock.now + .seconds(5)
        let calm = SystemSample(cpuPercent: 23, memoryUsed: 1, memoryTotal: 2, memoryPressure: .normal, disk: DiskSpace(free: 500_000_000_000, total: 1_000_000_000_000), thermalState: .nominal)
        monitor.apply(calm)
        while entry.context.pillStatus != nil {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }

        monitor.alwaysShowsCPU = true
        while entry.context.pillStatus?.ring == nil {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
        #expect(entry.context.pillStatus?.text == "CPU 23%")
        #expect(entry.context.pillStatus?.priority == .ambient)
        while defaults.object(forKey: "plugin.islet.system.alwaysShowCPU") as? Bool != true {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }

        var critical = calm
        critical.memoryPressure = .critical
        monitor.apply(critical)
        while entry.context.announcement?.text != "Memory almost full" || entry.context.pillStatus?.text != "Memory almost full" {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
        #expect(entry.context.pillStatus?.priority == .attention)

        monitor.thresholds.cpuPercent = 70
        while defaults.object(forKey: "plugin.islet.system.cpuThreshold") as? Int != 70 {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
        #expect(defaults.object(forKey: "plugin.islet.system.cpuSeconds") as? Int == 30)
    }
}
