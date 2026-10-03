import Foundation
import Synchronization
@testable import GitHubPlugin

final class StubClient: GitHubClient {
    private let results: Mutex<[Result<GitHubSnapshot, GitHubError>]>
    private let fallback: Result<GitHubSnapshot, GitHubError>
    let fetches = Mutex(0)

    init(_ results: [Result<GitHubSnapshot, GitHubError>], fallback: Result<GitHubSnapshot, GitHubError>? = nil) {
        self.results = Mutex(results)
        self.fallback = fallback ?? results.last ?? .success(GitHubSnapshot(mine: [], reviewRequested: []))
    }

    var fetchCount: Int {
        fetches.withLock { $0 }
    }

    func fetch() async throws -> GitHubSnapshot {
        fetches.withLock { $0 += 1 }
        let next = results.withLock { $0.isEmpty ? fallback : $0.removeFirst() }
        return try next.get()
    }
}

final class StubRunner: CommandRunning {
    let calls = Mutex<[[String]]>([])
    let respond: @Sendable ([String]) throws -> CommandResult

    init(respond: @escaping @Sendable ([String]) throws -> CommandResult) {
        self.respond = respond
    }

    var recordedCalls: [[String]] {
        calls.withLock { $0 }
    }

    func run(_ executable: URL, arguments: [String], timeout: Duration) async throws -> CommandResult {
        calls.withLock { $0.append(arguments) }
        return try respond(arguments)
    }
}

func pullRequest(_ number: Int, repository: String = "acme/app", updatedAt: Date = Date(timeIntervalSince1970: 1_790_000_000), isDraft: Bool = false, reviewDecision: ReviewDecision? = nil, author: String? = nil) -> PullRequest {
    PullRequest(
        number: number,
        title: "Pull request \(number)",
        url: URL(string: "https://github.com/\(repository)/pull/\(number)")!,
        repository: repository,
        isDraft: isDraft,
        reviewDecision: reviewDecision,
        author: author,
        updatedAt: updatedAt
    )
}

func snapshot(mine: Int, review: Int) -> GitHubSnapshot {
    GitHubSnapshot(mine: (0..<mine).map { pullRequest($0) }, reviewRequested: (0..<review).map { pullRequest(100 + $0, repository: "other/tool") })
}

func networkNeverChanges() -> AsyncStream<Bool> {
    AsyncStream { _ in }
}
