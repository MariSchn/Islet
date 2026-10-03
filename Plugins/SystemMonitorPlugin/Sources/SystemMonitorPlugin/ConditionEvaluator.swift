import Foundation
import IsletCore
import SwiftUI

struct AlertThresholds: Equatable, Sendable {
    var cpuPercent = 85
    var cpuSeconds = 30
    var batteryPercent = 20
    var batteryAttentionPercent = 10
    var diskFreeGigabytes = 10
}

struct SystemCondition: Equatable, Sendable {
    enum Kind: Int, CaseIterable, Sendable, Comparable {
        case cpu
        case memory
        case battery
        case thermal
        case disk

        static func < (lhs: Kind, rhs: Kind) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var systemImage: String {
            switch self {
            case .cpu: "cpu"
            case .memory: "memorychip"
            case .battery: "battery.25"
            case .thermal: "thermometer.high"
            case .disk: "internaldrive"
            }
        }
    }

    var kind: Kind
    var text: String
    var priority: PillStatus.Priority

    var pillStatus: PillStatus {
        PillStatus(text: text, systemImage: kind.systemImage, priority: priority)
    }

    var announcement: PillAnnouncement {
        PillAnnouncement(text: text, systemImage: kind.systemImage, priority: priority)
    }
}

struct ConditionEvaluator {
    struct Evaluation: Equatable {
        var conditions: [SystemCondition]
        var announcement: SystemCondition?
    }

    static let reannounceDelay: Duration = .seconds(60)
    static let gigabyte: Int64 = 1_000_000_000
    static let usedTint = Color.Resolved(red: 0.4, green: 0.65, blue: 1)
    static let freeTint = Color.Resolved(red: 0.45, green: 0.45, blue: 0.48)

    var thresholds: AlertThresholds
    private var cpuHighSince: ContinuousClock.Instant?
    private var announced: Set<SystemCondition.Kind> = []
    private var clearSince: [SystemCondition.Kind: ContinuousClock.Instant] = [:]

    init(thresholds: AlertThresholds = AlertThresholds()) {
        self.thresholds = thresholds
    }

    mutating func evaluate(_ sample: SystemSample, at now: ContinuousClock.Instant) -> Evaluation {
        if sample.cpuPercent > Double(thresholds.cpuPercent) {
            cpuHighSince = cpuHighSince ?? now
        } else {
            cpuHighSince = nil
        }
        let conditions = activeConditions(in: sample, at: now)
        let active = Set(conditions.map(\.kind))
        let announcement = Self.mostImportant(of: conditions.filter { !announced.contains($0.kind) })
        for kind in active {
            clearSince[kind] = nil
        }
        if let announcement {
            announced.insert(announcement.kind)
        }
        for kind in announced.subtracting(active) {
            if let since = clearSince[kind] {
                if now - since >= Self.reannounceDelay {
                    announced.remove(kind)
                    clearSince[kind] = nil
                }
            } else {
                clearSince[kind] = now
            }
        }
        return Evaluation(conditions: conditions, announcement: announcement)
    }

    private func activeConditions(in sample: SystemSample, at now: ContinuousClock.Instant) -> [SystemCondition] {
        var conditions: [SystemCondition] = []
        if let since = cpuHighSince, now - since >= .seconds(thresholds.cpuSeconds) {
            conditions.append(SystemCondition(kind: .cpu, text: "CPU \(SystemFormat.percent(sample.cpuPercent))", priority: .info))
        }
        switch sample.memoryPressure {
        case .normal: break
        case .warning: conditions.append(SystemCondition(kind: .memory, text: "Memory pressure high", priority: .info))
        case .critical: conditions.append(SystemCondition(kind: .memory, text: "Memory almost full", priority: .attention))
        }
        if let battery = sample.battery, !battery.isCharging, battery.percent <= thresholds.batteryPercent {
            let priority: PillStatus.Priority = battery.percent <= thresholds.batteryAttentionPercent ? .attention : .info
            conditions.append(SystemCondition(kind: .battery, text: "Battery \(battery.percent)%", priority: priority))
        }
        switch sample.thermalState {
        case .serious: conditions.append(SystemCondition(kind: .thermal, text: "Mac is hot", priority: .info))
        case .critical: conditions.append(SystemCondition(kind: .thermal, text: "Mac is hot", priority: .attention))
        default: break
        }
        if let disk = sample.disk, disk.free < Int64(thresholds.diskFreeGigabytes) * Self.gigabyte {
            conditions.append(SystemCondition(kind: .disk, text: "Disk almost full", priority: .info))
        }
        return conditions
    }

    static func mostImportant(of conditions: [SystemCondition]) -> SystemCondition? {
        conditions.min { lhs, rhs in
            lhs.priority != rhs.priority ? lhs.priority > rhs.priority : lhs.kind < rhs.kind
        }
    }

    static func pillStatus(for conditions: [SystemCondition], cpuPercent: Double?, alwaysShowsCPU: Bool) -> PillStatus? {
        if let condition = mostImportant(of: conditions) {
            return condition.pillStatus
        }
        guard alwaysShowsCPU, let cpuPercent else { return nil }
        let used = min(max(cpuPercent, 0), 100)
        let ring = PillStatus.Ring(segments: [
            .init(value: used, tint: usedTint),
            .init(value: 100 - used, tint: freeTint),
        ])
        return PillStatus(text: "CPU \(SystemFormat.percent(used))", systemImage: "cpu", priority: .ambient, ring: ring)
    }
}
