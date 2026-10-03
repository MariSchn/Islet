import Foundation
import Synchronization
@testable import SystemMonitorPlugin

final class FakeSystemReader: SystemReading {
    let timebase: MachTimebase
    private let names: [pid_t: String]
    private let state = Mutex<(uptime: UInt64, requests: [Bool])>((0, []))

    init(timebase: MachTimebase = MachTimebase(numer: 1, denom: 1), names: [pid_t: String] = [:]) {
        self.timebase = timebase
        self.names = names
    }

    var detailRequests: [Bool] {
        state.withLock { $0.requests }
    }

    func readCounters(includingDetails: Bool) -> SystemCounters {
        let uptime = state.withLock { state in
            state.requests.append(includingDetails)
            state.uptime += 1_000_000_000
            return state.uptime
        }
        return SystemCounters.fake(
            uptime: uptime,
            network: includingDetails ? [:] : nil,
            disk: DiskSpace(free: 1, total: 2),
            processes: includingDetails ? [] : nil
        )
    }

    func processName(of pid: pid_t) -> String? {
        names[pid]
    }
}

extension SystemCounters {
    static func fake(
        uptime: UInt64 = 0,
        ticks: [CPUTicks] = [],
        network: [String: NetworkBytes]? = nil,
        disk: DiskSpace? = nil,
        processes: [ProcessTime]? = nil
    ) -> SystemCounters {
        SystemCounters(
            uptimeNanoseconds: uptime,
            cpuTicks: ticks,
            memoryUsed: 8 << 30,
            memoryTotal: 16 << 30,
            memoryPressure: .normal,
            battery: nil,
            thermalState: .nominal,
            network: network,
            disk: disk,
            processes: processes
        )
    }
}
