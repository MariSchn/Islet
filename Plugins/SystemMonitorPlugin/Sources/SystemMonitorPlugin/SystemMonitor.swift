import Foundation
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
    var enabledRows: Set<SystemRow>
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

    init(sampler: SystemSampler, enabledRows: Set<SystemRow> = Set(SystemRow.allCases), visibleInterval: Duration = .seconds(1), hiddenInterval: Duration = .seconds(5)) {
        self.sampler = sampler
        self.enabledRows = enabledRows
        self.visibleInterval = visibleInterval
        self.hiddenInterval = hiddenInterval
    }

    var visibleRows: [SystemRow] {
        SystemRow.allCases.filter { row in
            enabledRows.contains(row) && (row != .battery || sample?.battery != nil)
        }
    }

    var isRunning: Bool { sampleTask != nil }

    func start() {
        guard sampleTask == nil else { return }
        startSampling()
    }

    func stop() {
        sampleTask?.cancel()
        sampleTask = nil
        sample = nil
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

    func apply(_ sample: SystemSample) {
        self.sample = sample
        cpuHistory.append(sample.cpuPercent)
        memoryHistory.append(Double(sample.memoryUsed))
        if let received = sample.networkIn, let sent = sample.networkOut {
            networkInHistory.append(received)
            networkOutHistory.append(sent)
        }
    }
}
