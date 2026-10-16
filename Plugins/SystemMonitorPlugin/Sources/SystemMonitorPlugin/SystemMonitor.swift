import Foundation
import IsletCore
import Observation

enum SystemRow: String, CaseIterable, Identifiable, Sendable {
    case cpu
    case memory
    case network
    case disk
    case battery
    case processes

    var id: Self { self }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .network: "Network"
        case .disk: "Disk"
        case .battery: "Battery"
        case .processes: "Top processes"
        }
    }

    var settingsKey: String {
        switch self {
        case .cpu: "showCPU"
        case .memory: "showMemory"
        case .network: "showNetwork"
        case .disk: "showDisk"
        case .battery: "showBattery"
        case .processes: "showTopProcesses"
        }
    }
}

@MainActor
@Observable
final class SystemMonitor {
    static let historyLength = 60

    private(set) var sample: SystemSample?
    private(set) var cpuHistory = RingBuffer<Double>(capacity: historyLength)
    private(set) var memoryHistory = RingBuffer<Double>(capacity: historyLength)
    private(set) var networkInHistory = RingBuffer<Double>(capacity: historyLength)
    private(set) var networkOutHistory = RingBuffer<Double>(capacity: historyLength)
    private(set) var conditions: [SystemCondition] = []
    private(set) var announcement: PillAnnouncement?
    var enabledRows: Set<SystemRow>
    var alwaysShowsCPU: Bool
    var thresholds: AlertThresholds {
        didSet { evaluator.thresholds = thresholds }
    }
    var isScreenVisible = false {
        didSet {
            guard isScreenVisible, !oldValue, sampleTask != nil else { return }
            startSampling()
        }
    }

    @ObservationIgnored private let sampler: SystemSampler
    @ObservationIgnored private let visibleInterval: Duration
    @ObservationIgnored private let hiddenInterval: Duration
    @ObservationIgnored private var sampleTask: Task<Void, Never>?
    @ObservationIgnored private var evaluator: ConditionEvaluator

    init(
        sampler: SystemSampler,
        enabledRows: Set<SystemRow> = Set(SystemRow.allCases),
        thresholds: AlertThresholds = AlertThresholds(),
        alwaysShowsCPU: Bool = false,
        visibleInterval: Duration = .seconds(1),
        hiddenInterval: Duration = .seconds(5)
    ) {
        self.sampler = sampler
        self.enabledRows = enabledRows
        self.thresholds = thresholds
        self.alwaysShowsCPU = alwaysShowsCPU
        evaluator = ConditionEvaluator(thresholds: thresholds)
        self.visibleInterval = visibleInterval
        self.hiddenInterval = hiddenInterval
    }

    var visibleRows: [SystemRow] {
        SystemRow.allCases.filter { row in
            enabledRows.contains(row) && (row != .battery || sample?.battery != nil)
        }
    }

    var isRunning: Bool { sampleTask != nil }

    var pillStatus: PillStatus? {
        ConditionEvaluator.pillStatus(for: conditions, cpuPercent: sample?.cpuPercent, alwaysShowsCPU: alwaysShowsCPU)
    }

    func start() {
        guard sampleTask == nil else { return }
        startSampling()
    }

    func stop() {
        sampleTask?.cancel()
        sampleTask = nil
        sample = nil
        conditions = []
        announcement = nil
        evaluator = ConditionEvaluator(thresholds: thresholds)
        cpuHistory.removeAll()
        memoryHistory.removeAll()
        networkInHistory.removeAll()
        networkOutHistory.removeAll()
    }

    private func startSampling() {
        sampleTask?.cancel()
        sampleTask = Task { [weak self, sampler] in
            while !Task.isCancelled {
                guard let includesDetails = self?.isScreenVisible else { return }
                let sample = await sampler.sample(includingDetails: includesDetails)
                guard !Task.isCancelled, let self else { return }
                apply(sample)
                try? await Task.sleep(for: isScreenVisible ? visibleInterval : hiddenInterval)
            }
        }
    }

    func apply(_ sample: SystemSample, at now: ContinuousClock.Instant = .now) {
        self.sample = sample
        let evaluation = evaluator.evaluate(sample, at: now)
        if evaluation.conditions != conditions {
            conditions = evaluation.conditions
        }
        if let started = evaluation.announcement {
            announcement = started.announcement
        }
        guard isScreenVisible else { return }
        cpuHistory.append(sample.cpuPercent)
        memoryHistory.append(Double(sample.memoryUsed))
        if let received = sample.networkIn, let sent = sample.networkOut {
            networkInHistory.append(received)
            networkOutHistory.append(sent)
        }
    }
}
