import Darwin
import Dispatch
import Foundation
import IOKit.ps
import os
import Synchronization

final class LiveSystemReader: SystemReading {
    let timebase: MachTimebase
    private let host = mach_host_self()
    private let pageSize: UInt64
    private let pressure = MemoryPressureMonitor()
    private let logger: Logger
    private let reportedFailures = Mutex<Set<String>>([])

    init(logger: Logger) {
        self.logger = logger
        var info = mach_timebase_info()
        mach_timebase_info(&info)
        timebase = MachTimebase(numer: info.numer, denom: info.denom)
        var size: vm_size_t = 0
        pageSize = host_page_size(host, &size) == KERN_SUCCESS && size > 0 ? UInt64(size) : UInt64(getpagesize())
    }

    func readCounters(includingDetails: Bool) -> SystemCounters {
        SystemCounters(
            uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
            cpuTicks: cpuTicks(),
            memoryUsed: memoryUsed(),
            memoryTotal: ProcessInfo.processInfo.physicalMemory,
            memoryPressure: pressure.level,
            battery: battery(),
            thermalState: ProcessInfo.processInfo.thermalState,
            network: includingDetails ? networkBytes() : nil,
            disk: includingDetails ? disk() : nil,
            processes: includingDetails ? processTimes() : nil
        )
    }

    func processName(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return Self.string(from: buffer)
    }

    private func cpuTicks() -> [CPUTicks] {
        var cores: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cores, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else {
            reportFailure("host_processor_info", code: result)
            return []
        }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        let states = Int(CPU_STATE_MAX)
        return (0..<Int(cores)).map { core in
            let base = core * states
            return CPUTicks(
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            )
        }
    }

    private func memoryUsed() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else {
            reportFailure("host_statistics64", code: result)
            return 0
        }
        return (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * pageSize
    }

    private func networkBytes() -> [String: NetworkBytes]? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
            reportFailure("sysctl NET_RT_IFLIST2", code: errno)
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else {
            reportFailure("sysctl NET_RT_IFLIST2", code: errno)
            return nil
        }
        var interfaces: [String: NetworkBytes] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if let name = interfaceName(index: message.ifm_index), name != "lo0" {
                        interfaces[name] = NetworkBytes(received: message.ifm_data.ifi_ibytes, sent: message.ifm_data.ifi_obytes)
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return interfaces
    }

    private func interfaceName(index: UInt16) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
        guard if_indextoname(UInt32(index), &buffer) != nil else { return nil }
        return Self.string(from: buffer)
    }

    private static func string(from buffer: [CChar]) -> String? {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return bytes.isEmpty ? nil : String(decoding: bytes, as: UTF8.self)
    }

    private func disk() -> DiskSpace? {
        do {
            let values = try URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
            guard let free = values.volumeAvailableCapacityForImportantUsage, let total = values.volumeTotalCapacity else { return nil }
            return DiskSpace(free: free, total: Int64(total))
        } catch {
            reportFailure("volume capacity", message: error.localizedDescription)
            return nil
        }
    }

    private func battery() -> BatteryState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0
            else { continue }
            let isPluggedIn = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let minutes = description[kIOPSTimeToEmptyKey] as? Int
            return BatteryState(
                percent: min(max(Int((Double(current) / Double(maximum) * 100).rounded()), 0), 100),
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isPluggedIn: isPluggedIn,
                minutesRemaining: !isPluggedIn ? minutes.flatMap { $0 > 0 ? $0 : nil } : nil
            )
        }
        return nil
    }

    private func processTimes() -> [ProcessTime]? {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else {
            reportFailure("proc_listallpids", code: errno)
            return nil
        }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 32)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0 else {
            reportFailure("proc_listallpids", code: errno)
            return nil
        }
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        return pids.prefix(min(Int(count), pids.count)).compactMap { pid in
            guard pid > 0 else { return nil }
            var info = proc_taskinfo()
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
            return ProcessTime(pid: pid, cpuTime: info.pti_total_user + info.pti_total_system)
        }
    }

    private func reportFailure(_ call: String, code: Int32) {
        reportFailure(call, message: "\(code)")
    }

    private func reportFailure(_ call: String, message: String) {
        let isNew = reportedFailures.withLock { $0.insert(call).inserted }
        guard isNew else { return }
        logger.error("\(call, privacy: .public) failed: \(message, privacy: .public)")
    }
}

final class MemoryPressureMonitor: Sendable {
    private struct State {
        var level: MemoryPressure = .normal
        var source: (any DispatchSourceMemoryPressure)?
    }

    private let state = Mutex(State())

    var level: MemoryPressure {
        state.withLock { state in
            if state.source == nil {
                state.source = makeSource()
            }
            return state.level
        }
    }

    deinit {
        state.withLock { $0.source?.cancel() }
    }

    private func makeSource() -> any DispatchSourceMemoryPressure {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .global(qos: .utility))
        source.setEventHandler { [weak self, source] in
            let event = source.data
            let level: MemoryPressure = event.contains(.critical) ? .critical : event.contains(.warning) ? .warning : .normal
            self?.state.withLock { $0.level = level }
        }
        source.activate()
        return source
    }
}
