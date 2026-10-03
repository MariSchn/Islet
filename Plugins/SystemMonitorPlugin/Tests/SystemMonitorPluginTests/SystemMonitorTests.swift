import Foundation
import Testing
@testable import SystemMonitorPlugin

@MainActor
struct SystemMonitorTests {
    @Test func readsDetailsOnlyWhileTheScreenIsVisible() async throws {
        let reader = FakeSystemReader()
        let monitor = SystemMonitor(sampler: SystemSampler(reader: reader), visibleInterval: .milliseconds(10), hiddenInterval: .milliseconds(10))
        monitor.start()
        defer { monitor.stop() }
        let deadline = ContinuousClock.now + .seconds(5)
        while reader.detailRequests.count < 2 {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(!reader.detailRequests.contains(true))
        #expect(monitor.sample?.networkIn == nil)

        monitor.isScreenVisible = true
        while monitor.sample?.networkIn == nil {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(reader.detailRequests.last == true)
    }

    @Test func keepsOneMinuteOfHistory() {
        let monitor = SystemMonitor(sampler: SystemSampler(reader: FakeSystemReader()))
        for index in 0..<70 {
            var sample = SystemSample(cpuPercent: Double(index), memoryUsed: UInt64(index), memoryTotal: 100, memoryPressure: .normal, thermalState: .nominal)
            if index.isMultiple(of: 2) {
                sample.networkIn = Double(index)
                sample.networkOut = Double(index) / 2
            }
            monitor.apply(sample)
        }
        #expect(monitor.cpuHistory.values == (10..<70).map(Double.init))
        #expect(monitor.memoryHistory.values == (10..<70).map(Double.init))
        #expect(monitor.networkInHistory.values == stride(from: 0, to: 70, by: 2).map(Double.init))
        #expect(monitor.networkOutHistory.values.last == 34)

        monitor.stop()
        #expect(monitor.sample == nil)
        #expect(monitor.cpuHistory.values.isEmpty)
    }
}
