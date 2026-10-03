import Foundation

struct CPUTicks: Sendable, Equatable {
    var user: UInt32
    var system: UInt32
    var idle: UInt32
    var nice: UInt32
}

struct NetworkBytes: Sendable, Equatable {
    var received: UInt64
    var sent: UInt64
}

struct ProcessTime: Sendable, Equatable {
    var pid: pid_t
    var cpuTime: UInt64
}

struct MachTimebase: Sendable, Equatable {
    var numer: UInt32
    var denom: UInt32

    func nanoseconds(_ ticks: UInt64) -> UInt64 {
        guard denom > 0 else { return 0 }
        let product = ticks.multipliedFullWidth(by: UInt64(numer))
        guard product.high < UInt64(denom) else { return .max }
        return UInt64(denom).dividingFullWidth(product).quotient
    }
}

struct SystemCounters: Sendable {
    var uptimeNanoseconds: UInt64
    var cpuTicks: [CPUTicks]
    var memoryUsed: UInt64
    var memoryTotal: UInt64
    var memoryPressure: MemoryPressure
    var battery: BatteryState?
    var thermalState: ProcessInfo.ThermalState
    var network: [String: NetworkBytes]?
    var disk: DiskSpace?
    var processes: [ProcessTime]?
}

protocol SystemReading: Sendable {
    var timebase: MachTimebase { get }
    func readCounters(includingDetails: Bool) -> SystemCounters
    func processName(of pid: pid_t) -> String?
}
