import Foundation
import Network
import Observation
import os

enum GitHubPhase: Equatable {
    case loading
    case ghMissing
    case notLoggedIn
    case failed(String)
    case loaded(GitHubSnapshot)

    var snapshot: GitHubSnapshot? {
        if case .loaded(let snapshot) = self { return snapshot }
        return nil
    }
}

typealias NetworkUpdates = @Sendable () -> AsyncStream<Bool>

enum NetworkStatus {
    static func updates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { continuation.yield($0.status == .satisfied) }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "islet.github.network"))
        }
    }
}

@MainActor
@Observable
final class GitHubController {
    private(set) var phase: GitHubPhase = .loading
    private(set) var isOnline = true
    var isScreenVisible = false {
        didSet {
            guard isScreenVisible, !oldValue else { return }
            refreshIfStale()
        }
    }

    @ObservationIgnored private let client: any GitHubClient
    @ObservationIgnored private let networkUpdates: NetworkUpdates
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let logger: Logger
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var networkTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private(set) var lastFetch: Date?
    @ObservationIgnored private(set) var failures = 0

    init(
        client: any GitHubClient,
        networkUpdates: @escaping NetworkUpdates = NetworkStatus.updates,
        now: @escaping @MainActor () -> Date = { .now },
        logger: Logger = Logger(subsystem: "Islet", category: "islet.github")
    ) {
        self.client = client
        self.networkUpdates = networkUpdates
        self.now = now
        self.logger = logger
    }

    var pollInterval: Duration {
        PollSchedule.interval(isScreenVisible: isScreenVisible, failures: failures)
    }

    func start() {
        guard pollTask == nil else { return }
        schedule(after: .zero)
        networkTask = Task { [weak self, networkUpdates] in
            for await online in networkUpdates() {
                guard let self else { return }
                networkChanged(online)
            }
        }
    }

    func stop() {
        generation += 1
        pollTask?.cancel()
        networkTask?.cancel()
        pollTask = nil
        networkTask = nil
        isRefreshing = false
        isOnline = true
        lastFetch = nil
        failures = 0
        phase = .loading
    }

    func refresh() async {
        guard isOnline else { return }
        generation += 1
        let requested = generation
        isRefreshing = true
        let outcome: Result<GitHubSnapshot, any Error>
        do {
            outcome = .success(try await client.fetch())
        } catch {
            outcome = .failure(error)
        }
        guard requested == generation else { return }
        isRefreshing = false
        if case .failure(let error) = outcome, error is CancellationError { return }
        lastFetch = now()
        switch outcome {
        case .success(let snapshot):
            failures = 0
            phase = .loaded(snapshot)
        case .failure(let error):
            failures += 1
            logger.error("Fetching pull requests failed: \(error.localizedDescription, privacy: .public)")
            phase = Self.phase(for: error)
        }
    }

    private static func phase(for error: any Error) -> GitHubPhase {
        switch error {
        case GitHubError.ghMissing: .ghMissing
        case GitHubError.notLoggedIn: .notLoggedIn
        default: .failed(error.localizedDescription)
        }
    }

    private func networkChanged(_ online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        guard online, pollTask != nil, !isRefreshing else { return }
        if failures > 0 {
            schedule(after: .zero)
        } else {
            refreshIfStale()
        }
    }

    private func refreshIfStale() {
        guard pollTask != nil, !isRefreshing else { return }
        schedule(after: PollSchedule.delayBeforeRefresh(lastFetch: lastFetch, now: now(), isScreenVisible: isScreenVisible, failures: failures))
    }

    private func schedule(after delay: Duration) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var delay = delay
            while !Task.isCancelled {
                if delay > .zero {
                    try? await Task.sleep(for: delay)
                }
                guard !Task.isCancelled, let self else { return }
                await refresh()
                delay = pollInterval
            }
        }
    }
}
