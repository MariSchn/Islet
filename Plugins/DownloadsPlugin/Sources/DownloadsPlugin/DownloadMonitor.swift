import Foundation
import Observation
import os

struct FinishedDownload: Equatable, Sendable {
    let id = UUID()
    let names: [String]
}

@MainActor
@Observable
final class DownloadMonitor {
    static let pollInterval: Duration = .seconds(1)

    private(set) var downloads: [ActiveDownload] = []
    private(set) var accessDenied = false
    private(set) var lastFinished: FinishedDownload?

    let folder: URL
    @ObservationIgnored private let recent: RecentDownloads
    @ObservationIgnored private let logger: Logger
    @ObservationIgnored private var tracker = DownloadTracker()
    @ObservationIgnored private var subscriber: Any?
    @ObservationIgnored private var progresses: [UUID: Progress] = [:]
    @ObservationIgnored private var observations: [UUID: [NSKeyValueObservation]] = [:]
    @ObservationIgnored private var source: (any DispatchSourceFileSystemObject)?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var isScanning = false
    @ObservationIgnored private var needsScan = false
    @ObservationIgnored private(set) var scanCount = 0

    init(folder: URL, recent: RecentDownloads, logger: Logger = Logger()) {
        self.folder = folder
        self.recent = recent
        self.logger = logger
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        subscribe()
        rescan()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        if let subscriber {
            Progress.removeSubscriber(subscriber)
        }
        subscriber = nil
        for observation in observations.values.joined() {
            observation.invalidate()
        }
        observations = [:]
        progresses = [:]
        source?.cancel()
        source = nil
        pollTask?.cancel()
        pollTask = nil
        needsScan = false
        tracker = DownloadTracker()
        refresh()
    }

    func rescan() {
        guard isRunning else { return }
        guard !isScanning else {
            needsScan = true
            return
        }
        isScanning = true
        let folder = folder
        let finalNames = tracker.listedNames
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result { try FolderListing.read(folder, finalNames: finalNames) }
            }.value
            self?.finishScan(result)
        }
    }

    private func finishScan(_ result: Result<FolderListing, any Error>) {
        isScanning = false
        scanCount += 1
        guard isRunning else { return }
        switch result {
        case .success(let listing):
            if accessDenied {
                accessDenied = false
            }
            startWatching()
            finish(tracker.apply(listing))
        case .failure(let error) where FolderListing.isAccessDenied(error):
            if !accessDenied {
                logger.error("Reading the Downloads folder was denied: \(error, privacy: .public)")
                accessDenied = true
            }
        case .failure(let error):
            logger.error("Could not read the Downloads folder: \(error, privacy: .public)")
        }
        refresh()
        updatePolling()
        if needsScan {
            needsScan = false
            rescan()
        }
    }

    private func finish(_ names: [String]) {
        guard !names.isEmpty else { return }
        for name in names {
            recent.add(folder.appending(path: name))
        }
        lastFinished = FinishedDownload(names: names)
    }

    private func refresh() {
        let current = tracker.downloads(now: .now)
        if current != downloads {
            downloads = current
        }
    }

    private func startWatching() {
        guard source == nil else { return }
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else {
            logger.error("Could not watch the Downloads folder: \(String(cString: strerror(errno)), privacy: .public)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.rescan() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    private func updatePolling() {
        if !tracker.hasRecentListedDownloads(now: .now) {
            pollTask?.cancel()
            pollTask = nil
        } else if pollTask == nil {
            startPolling()
        }
    }

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard let self, !Task.isCancelled else { return }
                guard tracker.hasRecentListedDownloads(now: .now) else {
                    refresh()
                    pollTask = nil
                    return
                }
                rescan()
            }
        }
    }

    private func subscribe() {
        subscriber = Progress.addSubscriber(forFileURL: folder) { [weak self] progress in
            let id = UUID()
            MainActor.assumeIsolated { self?.didPublish(progress, id: id) }
            return { [weak self] in
                MainActor.assumeIsolated { self?.didUnpublish(id) }
            }
        }
    }

    private func didPublish(_ progress: Progress, id: UUID) {
        guard isRunning, let snapshot = Self.snapshot(of: progress) else { return }
        progresses[id] = progress
        tracker.publish(id, snapshot)
        let changed: @Sendable (Progress) -> Void = { [weak self] progress in
            guard let snapshot = Self.snapshot(of: progress) else { return }
            Task { @MainActor [weak self] in self?.didUpdate(id, snapshot) }
        }
        observations[id] = [
            progress.observe(\.fractionCompleted) { @Sendable progress, _ in changed(progress) },
            progress.observe(\.fileURL) { @Sendable progress, _ in changed(progress) },
        ]
        refresh()
    }

    private func didUpdate(_ id: UUID, _ snapshot: PublishedProgress) {
        guard isRunning else { return }
        tracker.update(id, snapshot)
        refresh()
    }

    private func didUnpublish(_ id: UUID) {
        for observation in observations.removeValue(forKey: id) ?? [] {
            observation.invalidate()
        }
        if let progress = progresses.removeValue(forKey: id), let snapshot = Self.snapshot(of: progress) {
            tracker.update(id, snapshot)
        }
        guard isRunning else { return }
        if let name = tracker.unpublish(id) {
            finish([name])
        }
        refresh()
    }

    nonisolated static func snapshot(of progress: Progress) -> PublishedProgress? {
        guard let fileURL = progress.fileURL else { return nil }
        if let operation = progress.fileOperationKind, operation != .downloading { return nil }
        let fileName = fileURL.lastPathComponent
        let total = progress.totalUnitCount
        let completed = progress.completedUnitCount
        return PublishedProgress(
            name: DownloadName.finalName(forUnfinished: fileName) ?? fileName,
            fraction: progress.isIndeterminate ? nil : (min(max(progress.fractionCompleted, 0), 1) * 100).rounded(.down) / 100,
            bytes: progress.kind == .file && completed > 0 ? completed : nil,
            isComplete: progress.isFinished || (total > 0 && completed >= total)
        )
    }
}
