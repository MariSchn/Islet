import Foundation
import Testing
@testable import SystemMonitorPlugin

struct SystemSamplerTests {
    @Test func cpuLoadOfASingleCore() {
        let before = [CPUTicks(user: 100, system: 50, idle: 800, nice: 0)]
        let after = [CPUTicks(user: 160, system: 70, idle: 820, nice: 0)]
        #expect(SystemSampler.cpuPercent(from: before, to: after) == 80)
    }

    @Test func cpuLoadAveragesAllCores() {
        let before = [
            CPUTicks(user: 0, system: 0, idle: 0, nice: 0),
            CPUTicks(user: 10, system: 10, idle: 10, nice: 10),
        ]
        let after = [
            CPUTicks(user: 100, system: 0, idle: 0, nice: 0),
            CPUTicks(user: 10, system: 10, idle: 110, nice: 10),
        ]
        #expect(SystemSampler.cpuPercent(from: before, to: after) == 50)
    }

    @Test func cpuLoadHandlesWrappedCountersAndMismatchedSnapshots() {
        let before = [CPUTicks(user: .max - 9, system: 0, idle: 0, nice: 0)]
        let after = [CPUTicks(user: 10, system: 0, idle: 20, nice: 0)]
        #expect(SystemSampler.cpuPercent(from: before, to: after) == 50)
        #expect(SystemSampler.cpuPercent(from: before, to: after + after) == 0)
        #expect(SystemSampler.cpuPercent(from: after, to: after) == 0)
    }

    @Test func machTimeConvertsWithTheTimebase() {
        let timebase = MachTimebase(numer: 125, denom: 3)
        #expect(timebase.nanoseconds(3) == 125)
        #expect(timebase.nanoseconds(24_000_000) == 1_000_000_000)
        #expect(timebase.nanoseconds(300_000_000_000_000_000) == 12_500_000_000_000_000_000)
        #expect(timebase.nanoseconds(.max) == .max)
        #expect(MachTimebase(numer: 1, denom: 1).nanoseconds(42) == 42)
    }

    @Test func networkRateIgnoresCountersThatGoBackwards() {
        let before = ["en0": NetworkBytes(received: 5_000, sent: 1_000)]
        let rate = SystemSampler.networkRate(from: before, to: ["en0": NetworkBytes(received: 1_000, sent: 3_000)], nanoseconds: 2_000_000_000)
        #expect(rate.received == 0)
        #expect(rate.sent == 1_000)
    }

    @Test func networkRateSumsInterfacesPresentInBothSnapshots() {
        let before = ["en0": NetworkBytes(received: 0, sent: 0), "en1": NetworkBytes(received: 100, sent: 100)]
        let after = ["en0": NetworkBytes(received: 2_000, sent: 500), "en1": NetworkBytes(received: 1_100, sent: 100), "utun0": NetworkBytes(received: 9_999, sent: 9_999)]
        let rate = SystemSampler.networkRate(from: before, to: after, nanoseconds: 1_000_000_000)
        #expect(rate.received == 3_000)
        #expect(rate.sent == 500)
        let empty = SystemSampler.networkRate(from: before, to: after, nanoseconds: 0)
        #expect(empty.received == 0 && empty.sent == 0)
    }

    @Test func topProcessesUseMachTimeAndSkipReusedPIDs() {
        let timebase = MachTimebase(numer: 125, denom: 3)
        let old: [pid_t: UInt64] = [1: 0, 2: 0, 3: 0, 4: 0, 5: 1_000]
        let new = [
            ProcessTime(pid: 1, cpuTime: 24_000_000),
            ProcessTime(pid: 2, cpuTime: 12_000_000),
            ProcessTime(pid: 3, cpuTime: 2_400_000),
            ProcessTime(pid: 4, cpuTime: 240_000),
            ProcessTime(pid: 5, cpuTime: 10),
            ProcessTime(pid: 6, cpuTime: 48_000_000),
        ]
        let top = SystemSampler.topProcesses(from: old, to: new, nanoseconds: 1_000_000_000, timebase: timebase, limit: 3)
        #expect(top.map(\.pid) == [1, 2, 3])
        #expect(top.map(\.percent) == [100, 50, 10])
    }

    @Test func detailsNeedTwoVisibleSamplesAndResetWhileHidden() async {
        let sampler = SystemSampler(reader: FakeSystemReader(names: [7: "yes"]))
        let ticks = [CPUTicks(user: 0, system: 0, idle: 0, nice: 0)]
        let busy = [CPUTicks(user: 50, system: 0, idle: 50, nice: 0)]
        let first = await sampler.sample(from: .fake(uptime: 0, ticks: ticks, network: ["en0": NetworkBytes(received: 0, sent: 0)], processes: [ProcessTime(pid: 7, cpuTime: 0)]))
        #expect(first.cpuPercent == 0)
        #expect(first.networkIn == nil)
        #expect(first.topProcesses.isEmpty)

        let second = await sampler.sample(from: .fake(uptime: 1_000_000_000, ticks: busy, network: ["en0": NetworkBytes(received: 4_000, sent: 1_000)], processes: [ProcessTime(pid: 7, cpuTime: 500_000_000)]))
        #expect(second.cpuPercent == 50)
        #expect(second.networkIn == 4_000)
        #expect(second.networkOut == 1_000)
        #expect(second.topProcesses == [ProcessUsage(pid: 7, name: "yes", cpuPercent: 50)])

        let hidden = await sampler.sample(from: .fake(uptime: 6_000_000_000, ticks: busy))
        #expect(hidden.networkIn == nil)
        #expect(hidden.topProcesses.isEmpty)

        let visibleAgain = await sampler.sample(from: .fake(uptime: 7_000_000_000, ticks: busy, network: ["en0": NetworkBytes(received: 9_000, sent: 9_000)], processes: [ProcessTime(pid: 7, cpuTime: 900_000_000)]))
        #expect(visibleAgain.networkIn == nil)
        #expect(visibleAgain.topProcesses.isEmpty)
    }

    @Test func samplesTooCloseTogetherKeepTheLastRates() async {
        let sampler = SystemSampler(reader: FakeSystemReader(names: [7: "yes"]))
        let idle = [CPUTicks(user: 0, system: 0, idle: 0, nice: 0)]
        let half = [CPUTicks(user: 50, system: 0, idle: 50, nice: 0)]
        let full = [CPUTicks(user: 51, system: 0, idle: 50, nice: 0)]
        _ = await sampler.sample(from: .fake(uptime: 0, ticks: idle, network: ["en0": NetworkBytes(received: 0, sent: 0)], processes: [ProcessTime(pid: 7, cpuTime: 0)]))
        let second = await sampler.sample(from: .fake(uptime: 1_000_000_000, ticks: half, network: ["en0": NetworkBytes(received: 1_000, sent: 0)], processes: [ProcessTime(pid: 7, cpuTime: 500_000_000)]))
        let soon = await sampler.sample(from: .fake(uptime: 1_010_000_000, ticks: full, network: ["en0": NetworkBytes(received: 1_100, sent: 0)], processes: [ProcessTime(pid: 7, cpuTime: 510_000_000)]))
        #expect(soon.cpuPercent == second.cpuPercent)
        #expect(soon.networkIn == second.networkIn)
        #expect(soon.topProcesses == second.topProcesses)

        let later = await sampler.sample(from: .fake(uptime: 2_000_000_000, ticks: full, network: ["en0": NetworkBytes(received: 3_000, sent: 0)], processes: [ProcessTime(pid: 7, cpuTime: 750_000_000)]))
        #expect(later.cpuPercent == 100)
        #expect(later.networkIn == 2_000)
        #expect(later.topProcesses.first?.cpuPercent == 25)
    }
}
