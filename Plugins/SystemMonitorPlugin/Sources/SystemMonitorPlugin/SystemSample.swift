import Foundation

enum MemoryPressure: Int, Sendable, Comparable {
    case normal
    case warning
    case critical

    static func < (lhs: MemoryPressure, rhs: MemoryPressure) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct BatteryState: Sendable, Equatable {
    var percent: Int
    var isCharging: Bool
    var isPluggedIn: Bool
    var minutesRemaining: Int?
}

struct DiskSpace: Sendable, Equatable {
    var free: Int64
    var total: Int64

    var usedFraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(total - free) / Double(total), 0), 1)
    }
}

struct ProcessUsage: Sendable, Equatable, Identifiable {
    var pid: pid_t
    var name: String
    var cpuPercent: Double

    var id: pid_t { pid }
}

struct SystemSample: Sendable, Equatable {
    var cpuPercent: Double
    var memoryUsed: UInt64
    var memoryTotal: UInt64
    var memoryPressure: MemoryPressure
    var networkIn: Double?
    var networkOut: Double?
    var disk: DiskSpace?
    var battery: BatteryState?
    var thermalState: ProcessInfo.ThermalState
    var topProcesses: [ProcessUsage] = []
}

struct RingBuffer<Element: Sendable>: Sendable {
    let capacity: Int
    private var storage: [Element] = []
    private var head = 0

    init(capacity: Int) {
        self.capacity = max(capacity, 1)
    }

    var values: [Element] {
        Array(storage[head...] + storage[..<head])
    }

    var count: Int { storage.count }

    mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    mutating func removeAll() {
        storage.removeAll()
        head = 0
    }
}
