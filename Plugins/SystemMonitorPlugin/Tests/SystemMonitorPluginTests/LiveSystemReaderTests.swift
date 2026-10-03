import Foundation
import os
import Synchronization
import Testing
@testable import SystemMonitorPlugin

struct LiveSystemReaderTests {
    private let reader = LiveSystemReader(logger: Logger(subsystem: "SystemMonitorPluginTests", category: "reader"))

    @Test func readsPlausibleCounters() {
        let hidden = reader.readCounters(includingDetails: false)
        #expect(hidden.cpuTicks.count == ProcessInfo.processInfo.processorCount)
        #expect(hidden.memoryTotal == ProcessInfo.processInfo.physicalMemory)
        #expect(hidden.memoryUsed > 0 && hidden.memoryUsed <= hidden.memoryTotal)
        #expect(hidden.network == nil && hidden.processes == nil)
        #expect((hidden.disk?.total ?? 0) > 0)

        let visible = reader.readCounters(includingDetails: true)
        #expect(visible.uptimeNanoseconds > hidden.uptimeNanoseconds)
        #expect(visible.network?.keys.contains("lo0") == false)
        #expect((visible.disk?.total ?? 0) > 0)
        #expect(visible.processes?.contains { $0.pid == getpid() } == true)
        #expect(reader.processName(of: getpid())?.isEmpty == false)
        #expect(reader.timebase.denom > 0)
    }

    @Test func readsDiskSpaceOncePerInterval() {
        let reads = Mutex(0)
        let reader = LiveSystemReader(logger: Logger(subsystem: "SystemMonitorPluginTests", category: "reader")) { _ in
            let count = reads.withLock { $0 += 1; return $0 }
            return DiskSpace(free: Int64(count), total: 100)
        }
        #expect(reader.disk(at: 1_000)?.free == 1)
        #expect(reader.disk(at: 1_000 + LiveSystemReader.diskInterval - 1)?.free == 1)
        #expect(reader.disk(at: 1_000 + LiveSystemReader.diskInterval)?.free == 2)
        #expect(reads.withLock { $0 } == 2)
    }
}
