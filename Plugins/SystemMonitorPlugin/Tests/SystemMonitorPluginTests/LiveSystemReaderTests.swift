import Foundation
import os
import Testing
@testable import SystemMonitorPlugin

struct LiveSystemReaderTests {
    private let reader = LiveSystemReader(logger: Logger(subsystem: "SystemMonitorPluginTests", category: "reader"))

    @Test func readsPlausibleCounters() {
        let hidden = reader.readCounters(includingDetails: false)
        #expect(hidden.cpuTicks.count == ProcessInfo.processInfo.processorCount)
        #expect(hidden.memoryTotal == ProcessInfo.processInfo.physicalMemory)
        #expect(hidden.memoryUsed > 0 && hidden.memoryUsed <= hidden.memoryTotal)
        #expect(hidden.network == nil && hidden.disk == nil && hidden.processes == nil)

        let visible = reader.readCounters(includingDetails: true)
        #expect(visible.uptimeNanoseconds > hidden.uptimeNanoseconds)
        #expect(visible.network?.keys.contains("lo0") == false)
        #expect((visible.disk?.total ?? 0) > 0)
        #expect(visible.processes?.contains { $0.pid == getpid() } == true)
        #expect(reader.processName(of: getpid())?.isEmpty == false)
        #expect(reader.timebase.denom > 0)
    }
}
