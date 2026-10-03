import Foundation
import IsletCore
import Testing
@testable import SystemMonitorPlugin

struct ConditionEvaluatorTests {
    private let start = ContinuousClock.now

    private func sample(
        cpu: Double = 10,
        pressure: MemoryPressure = .normal,
        battery: BatteryState? = nil,
        thermal: ProcessInfo.ThermalState = .nominal,
        diskFree: Int64 = 500_000_000_000
    ) -> SystemSample {
        SystemSample(
            cpuPercent: cpu,
            memoryUsed: 8 << 30,
            memoryTotal: 16 << 30,
            memoryPressure: pressure,
            disk: DiskSpace(free: diskFree, total: 1_000_000_000_000),
            battery: battery,
            thermalState: thermal
        )
    }

    private func at(_ seconds: Int) -> ContinuousClock.Instant {
        start + .seconds(seconds)
    }

    @Test func cpuConditionNeedsThirtySecondsInARow() {
        var evaluator = ConditionEvaluator()
        for second in stride(from: 0, to: 30, by: 5) {
            #expect(evaluator.evaluate(sample(cpu: 97), at: at(second)).conditions.isEmpty)
        }
        let evaluation = evaluator.evaluate(sample(cpu: 97), at: at(30))
        #expect(evaluation.conditions == [SystemCondition(kind: .cpu, text: "CPU 97%", priority: .info)])
        #expect(evaluation.announcement?.text == "CPU 97%")
        #expect(evaluator.evaluate(sample(cpu: 92), at: at(35)).conditions.map(\.text) == ["CPU 92%"])

        #expect(evaluator.evaluate(sample(cpu: 85), at: at(40)).conditions.isEmpty)
        #expect(evaluator.evaluate(sample(cpu: 99), at: at(45)).conditions.isEmpty)
        #expect(evaluator.evaluate(sample(cpu: 99), at: at(70)).conditions.isEmpty)
        #expect(evaluator.evaluate(sample(cpu: 99), at: at(75)).conditions.map(\.kind) == [.cpu])
    }

    @Test func announcesAgainOnlyAfterAMinuteClear() {
        var evaluator = ConditionEvaluator()
        #expect(evaluator.evaluate(sample(pressure: .warning), at: at(0)).announcement?.text == "Memory pressure high")
        #expect(evaluator.evaluate(sample(pressure: .warning), at: at(5)).announcement == nil)
        #expect(evaluator.evaluate(sample(), at: at(10)).conditions.isEmpty)
        let back = evaluator.evaluate(sample(pressure: .critical), at: at(40))
        #expect(back.conditions.map(\.text) == ["Memory almost full"])
        #expect(back.announcement == nil)
        #expect(evaluator.evaluate(sample(), at: at(50)).announcement == nil)
        #expect(evaluator.evaluate(sample(), at: at(105)).announcement == nil)
        #expect(evaluator.evaluate(sample(pressure: .warning), at: at(106)).announcement == nil)
        #expect(evaluator.evaluate(sample(), at: at(110)).announcement == nil)
        #expect(evaluator.evaluate(sample(), at: at(170)).announcement == nil)
        #expect(evaluator.evaluate(sample(pressure: .warning), at: at(175)).announcement?.text == "Memory pressure high")
    }

    @Test func pillPrefersPriorityThenListOrder() {
        var evaluator = ConditionEvaluator()
        let onBattery = BatteryState(percent: 8, isCharging: false, isPluggedIn: false)
        _ = evaluator.evaluate(sample(cpu: 99), at: at(0))
        let everything = evaluator.evaluate(sample(cpu: 99, pressure: .warning, battery: onBattery, thermal: .critical, diskFree: 1_000), at: at(30))
        #expect(everything.conditions.map(\.kind) == SystemCondition.Kind.allCases)
        #expect(everything.announcement?.kind == .battery)
        let ongoing = sample(cpu: 99, pressure: .warning, battery: onBattery, thermal: .critical, diskFree: 1_000)
        let following = (31...35).map { evaluator.evaluate(ongoing, at: at($0)).announcement?.kind }
        #expect(following == [.thermal, .cpu, .memory, .disk, nil])
        let pill = ConditionEvaluator.pillStatus(for: everything.conditions, cpuPercent: 99, alwaysShowsCPU: true)
        #expect(pill == PillStatus(text: "Battery 8%", systemImage: "battery.25", priority: .attention))

        let infoOnly = evaluator.evaluate(sample(cpu: 99, thermal: .serious, diskFree: 1_000), at: at(35))
        #expect(ConditionEvaluator.pillStatus(for: infoOnly.conditions, cpuPercent: 99, alwaysShowsCPU: false) == PillStatus(text: "CPU 99%", systemImage: "cpu", priority: .info))
        let disk = evaluator.evaluate(sample(diskFree: 1_000), at: at(40))
        #expect(ConditionEvaluator.pillStatus(for: disk.conditions, cpuPercent: 10, alwaysShowsCPU: false) == PillStatus(text: "Disk almost full", systemImage: "internaldrive", priority: .info))
        let thermal = evaluator.evaluate(sample(thermal: .critical), at: at(45))
        #expect(ConditionEvaluator.pillStatus(for: thermal.conditions, cpuPercent: 10, alwaysShowsCPU: false) == PillStatus(text: "Mac is hot", systemImage: "thermometer.high", priority: .attention))
    }

    @Test func batteryAlertsOnlyWhileNotCharging() {
        var evaluator = ConditionEvaluator()
        func battery(_ percent: Int, charging: Bool) -> [SystemCondition] {
            evaluator.evaluate(sample(battery: BatteryState(percent: percent, isCharging: charging, isPluggedIn: charging)), at: at(0)).conditions
        }
        #expect(battery(15, charging: true).isEmpty)
        #expect(battery(5, charging: true).isEmpty)
        #expect(battery(21, charging: false).isEmpty)
        #expect(battery(20, charging: false) == [SystemCondition(kind: .battery, text: "Battery 20%", priority: .info)])
        #expect(battery(18, charging: false) == [SystemCondition(kind: .battery, text: "Battery 18%", priority: .info)])
        #expect(battery(10, charging: false) == [SystemCondition(kind: .battery, text: "Battery 10%", priority: .attention)])
        #expect(evaluator.evaluate(sample(), at: at(0)).conditions.isEmpty)
    }

    @Test func thresholdsComeFromTheSettings() {
        var evaluator = ConditionEvaluator(thresholds: AlertThresholds(cpuPercent: 50, cpuSeconds: 10, batteryPercent: 40, batteryAttentionPercent: 30, diskFreeGigabytes: 100))
        _ = evaluator.evaluate(sample(cpu: 60), at: at(0))
        let evaluation = evaluator.evaluate(sample(cpu: 60, battery: BatteryState(percent: 35, isCharging: false, isPluggedIn: false), diskFree: 99_000_000_000), at: at(10))
        #expect(evaluation.conditions.map(\.kind) == [.cpu, .battery, .disk])
        #expect(evaluation.conditions.map(\.priority) == [.info, .info, .info])
        #expect(evaluator.evaluate(sample(diskFree: 100_000_000_000), at: at(15)).conditions.isEmpty)
    }

    @Test func alwaysOnRingWhenNothingIsWrong() {
        #expect(ConditionEvaluator.pillStatus(for: [], cpuPercent: 23, alwaysShowsCPU: false) == nil)
        #expect(ConditionEvaluator.pillStatus(for: [], cpuPercent: nil, alwaysShowsCPU: true) == nil)
        let ring = PillStatus.Ring(segments: [
            .init(value: 23, tint: ConditionEvaluator.usedTint),
            .init(value: 77, tint: ConditionEvaluator.freeTint),
        ])
        #expect(ConditionEvaluator.pillStatus(for: [], cpuPercent: 23, alwaysShowsCPU: true) == PillStatus(text: "CPU 23%", systemImage: "cpu", priority: .ambient, ring: ring))
        let hot = SystemCondition(kind: .thermal, text: "Mac is hot", priority: .info)
        #expect(ConditionEvaluator.pillStatus(for: [hot], cpuPercent: 23, alwaysShowsCPU: true) == hot.pillStatus)
    }
}
