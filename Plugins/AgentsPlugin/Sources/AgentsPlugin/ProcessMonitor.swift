import Foundation

@MainActor
final class ProcessMonitor {
    static let pollInterval: Duration = .seconds(2)

    private var task: Task<Void, Never>?
    private let onPoll: () -> Void

    init(onPoll: @escaping () -> Void) {
        self.onPoll = onPoll
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled else { return }
                self?.onPoll()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    nonisolated static func isRunning(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    nonisolated static var bootTime: Date {
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &time, &size, nil, 0) == 0 else { return .distantPast }
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_usec) / 1_000_000)
    }
}
