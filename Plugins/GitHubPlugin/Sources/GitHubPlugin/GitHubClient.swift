import Foundation

protocol GitHubClient: Sendable {
    func fetch() async throws -> GitHubSnapshot
}

enum GitHubError: LocalizedError, Equatable {
    case ghMissing
    case notLoggedIn
    case timedOut
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .ghMissing: "Install the GitHub CLI: brew install gh"
        case .notLoggedIn: "Log in with: gh auth login"
        case .timedOut: "The GitHub CLI did not respond within \(GhClient.timeout.components.seconds) seconds."
        case .failed(let message): message
        }
    }
}

struct GhClient: GitHubClient {
    static let timeout: Duration = .seconds(20)
    static let query = """
        query {
          mine: search(query: "is:open is:pr author:@me archived:false", type: ISSUE, first: 20) {
            nodes { ... on PullRequest { number title url isDraft reviewDecision updatedAt repository { nameWithOwner } } }
          }
          review: search(query: "is:open is:pr review-requested:@me archived:false", type: ISSUE, first: 20) {
            nodes { ... on PullRequest { number title url isDraft updatedAt author { login } repository { nameWithOwner } } }
          }
        }
        """

    let locator: GhLocator
    let runner: any CommandRunning

    init(locator: GhLocator = GhLocator(), runner: any CommandRunning = ProcessRunner()) {
        self.locator = locator
        self.runner = runner
    }

    func fetch() async throws -> GitHubSnapshot {
        guard let gh = await locator.locate() else { throw GitHubError.ghMissing }
        let result = try await run(gh, ["api", "graphql", "--hostname", "github.com", "-f", "query=\(Self.query)"])
        guard result.status == 0 else {
            let auth = try await run(gh, ["auth", "status", "--hostname", "github.com"])
            if auth.status != 0 { throw GitHubError.notLoggedIn }
            throw GitHubError.failed(Self.message(from: result))
        }
        return try GitHubSnapshot.decode(result.output)
    }

    private func run(_ gh: URL, _ arguments: [String]) async throws -> CommandResult {
        do {
            return try await runner.run(gh, arguments: arguments, timeout: Self.timeout)
        } catch CommandError.timedOut {
            throw GitHubError.timedOut
        }
    }

    static func message(from result: CommandResult) -> String {
        let text = String(decoding: result.errorOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let line = text.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
        let message = line.hasPrefix("gh: ") ? String(line.dropFirst(4)) : line
        return message.isEmpty ? "The GitHub CLI exited with status \(result.status)." : message
    }
}

actor GhLocator {
    static let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]

    private let isExecutable: @Sendable (String) -> Bool
    private let shellLookup: @Sendable () async throws -> String?
    private var shellResult: String??

    init(
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        shellLookup: @escaping @Sendable () async throws -> String? = GhLocator.lookUpInLoginShell
    ) {
        self.isExecutable = isExecutable
        self.shellLookup = shellLookup
    }

    func locate() async -> URL? {
        if let path = Self.candidates.first(where: isExecutable) {
            return URL(filePath: path)
        }
        let path: String?
        if let cached = shellResult {
            path = cached
        } else {
            do {
                path = try await shellLookup()
            } catch {
                return nil
            }
            shellResult = .some(path)
        }
        guard let path, isExecutable(path) else { return nil }
        return URL(filePath: path)
    }

    static func lookUpInLoginShell() async throws -> String? {
        let result = try await ProcessRunner().run(URL(filePath: "/bin/zsh"), arguments: ["-lc", "command -v gh"], timeout: GhClient.timeout)
        guard result.status == 0 else { return nil }
        let lines = String(decoding: result.output, as: UTF8.self).split(whereSeparator: \.isNewline)
        let path = lines.last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return path.hasPrefix("/") ? path : nil
    }
}
