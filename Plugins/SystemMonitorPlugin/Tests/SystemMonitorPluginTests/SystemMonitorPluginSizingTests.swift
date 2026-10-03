import Foundation
import Testing
@testable import SystemMonitorPlugin

@MainActor
struct SystemMonitorPluginSizingTests {
    @Test func heightFollowsTheEnabledRows() {
        #expect(SystemMonitorPlugin.contentSize(for: SystemRow.allCases) == CGSize(width: 420, height: 24 + 5 * 28 + 20 + 3 * 28))
        #expect(SystemMonitorPlugin.contentSize(for: [.cpu]) == CGSize(width: 420, height: 52))
        #expect(SystemMonitorPlugin.contentSize(for: [.cpu, .memory, .network, .disk]) == CGSize(width: 420, height: 24 + 4 * 28))
        #expect(SystemMonitorPlugin.contentSize(for: [.processes]) == CGSize(width: 420, height: 24 + 20 + 3 * 28))
        #expect(SystemMonitorPlugin.contentSize(for: []) == CGSize(width: 420, height: 80))
    }

    @Test func batteryRowOnlyCountsWithABattery() {
        let monitor = SystemMonitor(sampler: SystemSampler(reader: FakeSystemReader()))
        #expect(!monitor.visibleRows.contains(.battery))
        var sample = SystemSample(cpuPercent: 0, memoryUsed: 0, memoryTotal: 1, memoryPressure: .normal, thermalState: .nominal)
        monitor.apply(sample)
        #expect(monitor.visibleRows == [.cpu, .memory, .network, .disk, .processes])
        sample.battery = BatteryState(percent: 50, isCharging: false, isPluggedIn: false)
        monitor.apply(sample)
        #expect(monitor.visibleRows == SystemRow.allCases)
        monitor.enabledRows = [.battery, .disk, .cpu]
        #expect(monitor.visibleRows == [.cpu, .disk, .battery])
        #expect(SystemMonitorPlugin.contentSize(for: monitor.visibleRows) == CGSize(width: 420, height: 24 + 3 * 28))
    }
}
