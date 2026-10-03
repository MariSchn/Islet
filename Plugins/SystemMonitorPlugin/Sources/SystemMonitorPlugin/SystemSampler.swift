import Foundation

actor SystemSampler {
    static let topProcessCount = 3
    static let minimumInterval: UInt64 = 250_000_000

    private let reader: any SystemReading
    private var previousTicks: (at: UInt64, ticks: [CPUTicks])?
    private var previousNetwork: (at: UInt64, bytes: [String: NetworkBytes])?
    private var previousProcesses: (at: UInt64, times: [pid_t: UInt64])?
    private var lastCPUPercent: Double = 0
    private var lastNetworkRate: (received: Double, sent: Double)?
    private var lastTopProcesses: [ProcessUsage] = []

    init(reader: any SystemReading) {
        self.reader = reader
    }

    func sample(includingDetails: Bool) -> SystemSample {
        sample(from: reader.readCounters(includingDetails: includingDetails))
    }

    func sample(from counters: SystemCounters) -> SystemSample {
        let now = counters.uptimeNanoseconds
        if let previous = previousTicks {
            let elapsed = Self.elapsed(from: previous.at, to: now)
            if elapsed >= Self.minimumInterval {
                lastCPUPercent = Self.cpuPercent(from: previous.ticks, to: counters.cpuTicks)
                previousTicks = (now, counters.cpuTicks)
            }
        } else {
            previousTicks = (now, counters.cpuTicks)
        }

        if let network = counters.network {
            if let previous = previousNetwork {
                let elapsed = Self.elapsed(from: previous.at, to: now)
                if elapsed >= Self.minimumInterval {
                    lastNetworkRate = Self.networkRate(from: previous.bytes, to: network, nanoseconds: elapsed)
                    previousNetwork = (now, network)
                }
            } else {
                previousNetwork = (now, network)
            }
        } else {
            previousNetwork = nil
            lastNetworkRate = nil
        }

        if let processes = counters.processes {
            if let previous = previousProcesses {
                let elapsed = Self.elapsed(from: previous.at, to: now)
                if elapsed >= Self.minimumInterval {
                    let usage = Self.topProcesses(from: previous.times, to: processes, nanoseconds: elapsed, timebase: reader.timebase, limit: Self.topProcessCount)
                    lastTopProcesses = usage.map { ProcessUsage(pid: $0.pid, name: reader.processName(of: $0.pid) ?? "\($0.pid)", cpuPercent: $0.percent) }
                    previousProcesses = (now, Self.times(of: processes))
                }
            } else {
                previousProcesses = (now, Self.times(of: processes))
            }
        } else {
            previousProcesses = nil
            lastTopProcesses = []
        }

        return SystemSample(
            cpuPercent: lastCPUPercent,
            memoryUsed: counters.memoryUsed,
            memoryTotal: counters.memoryTotal,
            memoryPressure: counters.memoryPressure,
            networkIn: lastNetworkRate?.received,
            networkOut: lastNetworkRate?.sent,
            disk: counters.disk,
            battery: counters.battery,
            thermalState: counters.thermalState,
            topProcesses: lastTopProcesses
        )
    }

    static func elapsed(from start: UInt64, to end: UInt64) -> UInt64 {
        end > start ? end - start : 0
    }

    static func times(of processes: [ProcessTime]) -> [pid_t: UInt64] {
        Dictionary(processes.map { ($0.pid, $0.cpuTime) }, uniquingKeysWith: { $1 })
    }

    static func cpuPercent(from old: [CPUTicks], to new: [CPUTicks]) -> Double {
        guard old.count == new.count, !new.isEmpty else { return 0 }
        var busy: UInt64 = 0
        var total: UInt64 = 0
        for (before, after) in zip(old, new) {
            let user = UInt64(after.user &- before.user)
            let system = UInt64(after.system &- before.system)
            let nice = UInt64(after.nice &- before.nice)
            let idle = UInt64(after.idle &- before.idle)
            busy += user + system + nice
            total += user + system + nice + idle
        }
        guard total > 0 else { return 0 }
        return Double(busy) / Double(total) * 100
    }

    static func networkRate(from old: [String: NetworkBytes], to new: [String: NetworkBytes], nanoseconds: UInt64) -> (received: Double, sent: Double) {
        guard nanoseconds > 0 else { return (0, 0) }
        var received: UInt64 = 0
        var sent: UInt64 = 0
        for (name, after) in new {
            guard let before = old[name] else { continue }
            if after.received >= before.received {
                received += after.received - before.received
            }
            if after.sent >= before.sent {
                sent += after.sent - before.sent
            }
        }
        let seconds = Double(nanoseconds) / 1_000_000_000
        return (Double(received) / seconds, Double(sent) / seconds)
    }

    static func topProcesses(from old: [pid_t: UInt64], to new: [ProcessTime], nanoseconds: UInt64, timebase: MachTimebase, limit: Int) -> [(pid: pid_t, percent: Double)] {
        guard nanoseconds > 0 else { return [] }
        let usage: [(pid: pid_t, percent: Double)] = new.compactMap { process in
            guard let before = old[process.pid], process.cpuTime >= before else { return nil }
            let busy = timebase.nanoseconds(process.cpuTime - before)
            return (process.pid, Double(busy) / Double(nanoseconds) * 100)
        }
        return Array(usage.sorted { $0.percent != $1.percent ? $0.percent > $1.percent : $0.pid < $1.pid }.prefix(limit))
    }
}
