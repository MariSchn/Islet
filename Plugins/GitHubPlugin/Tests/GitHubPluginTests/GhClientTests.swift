import Foundation
import Testing
@testable import GitHubPlugin

struct GhClientTests {
    private func locator(found: Bool = true) -> GhLocator {
        GhLocator(isExecutable: { found && $0 == "/opt/homebrew/bin/gh" }, shellLookup: { nil })
    }

    private func result(_ status: Int32, output: String = "", error: String = "") -> CommandResult {
        CommandResult(status: status, output: Data(output.utf8), errorOutput: Data(error.utf8))
    }

    @Test func runsTheGraphQLQueryAndDecodesIt() async throws {
        let runner = StubRunner { _ in self.result(0, output: GitHubSnapshotTests.fixture) }
        let snapshot = try await GhClient(locator: locator(), runner: runner).fetch()
        #expect(snapshot.mine.count == 3)
        #expect(runner.recordedCalls == [["api", "graphql", "--hostname", "github.com", "-f", "query=\(GhClient.query)"]])
    }

    @Test func reportsAMissingCLIWithoutRunningAnything() async {
        let runner = StubRunner { _ in self.result(0) }
        await #expect(throws: GitHubError.ghMissing) {
            try await GhClient(locator: locator(found: false), runner: runner).fetch()
        }
        #expect(runner.recordedCalls.isEmpty)
    }

    @Test func reportsAMissingLoginWhenAuthStatusFails() async {
        let runner = StubRunner { arguments in
            arguments.first == "auth" ? self.result(1, error: "You are not logged into any GitHub hosts.") : self.result(4, error: "To get started with GitHub CLI, please run:  gh auth login")
        }
        await #expect(throws: GitHubError.notLoggedIn) {
            try await GhClient(locator: locator(), runner: runner).fetch()
        }
        #expect(runner.recordedCalls.last == ["auth", "status", "--hostname", "github.com"])
    }

    @Test func reportsTheCLIErrorWhenLoggedIn() async {
        let runner = StubRunner { arguments in
            arguments.first == "auth" ? self.result(0) : self.result(1, error: "warning\ngh: API rate limit exceeded\n")
        }
        await #expect(throws: GitHubError.failed("API rate limit exceeded")) {
            try await GhClient(locator: locator(), runner: runner).fetch()
        }
    }

    @Test func fallsBackToTheExitStatusWithoutAMessage() {
        #expect(GhClient.message(from: result(2)) == "The GitHub CLI exited with status 2.")
    }

    @Test func mapsATimeout() async {
        let runner = StubRunner { _ in throw CommandError.timedOut }
        await #expect(throws: GitHubError.timedOut) {
            try await GhClient(locator: locator(), runner: runner).fetch()
        }
    }

    @Test func processRunnerCollectsOutputAndStatus() async throws {
        let result = try await ProcessRunner().run(URL(filePath: "/bin/sh"), arguments: ["-c", "echo out; echo err >&2; exit 3"], timeout: .seconds(10))
        #expect(result == self.result(3, output: "out\n", error: "err\n"))
    }

    @Test func processRunnerStopsACommandAfterTheTimeout() async {
        let start = ContinuousClock.now
        await #expect(throws: CommandError.self) {
            try await ProcessRunner().run(URL(filePath: "/bin/sleep"), arguments: ["10"], timeout: .milliseconds(200))
        }
        #expect(ContinuousClock.now - start < .seconds(8))
    }

    @Test func processRunnerKillsACommandThatIgnoresTermination() async {
        let start = ContinuousClock.now
        await #expect(throws: CommandError.self) {
            try await ProcessRunner().run(URL(filePath: "/bin/sh"), arguments: ["-c", "trap '' TERM; sleep 6; sleep 6"], timeout: .milliseconds(200))
        }
        #expect(ContinuousClock.now - start < .seconds(10))
    }
}
