import Foundation
import IsletCore
import Testing
@testable import GitHubPlugin

@MainActor
struct GitHubChangesTests {
    struct Case: CustomTestStringConvertible, Sendable {
        var name: String
        var before: PullRequest
        var after: PullRequest
        var expected: [GitHubChange.Kind]

        var testDescription: String { name }
    }

    nonisolated static let cases: [Case] = [
        Case(name: "pending to failing", before: pullRequest(1, checks: .pending), after: pullRequest(1, checks: .failing), expected: [.checksFailed]),
        Case(name: "pending to passing", before: pullRequest(1, checks: .pending), after: pullRequest(1, checks: .passing), expected: [.checksPassed]),
        Case(name: "pending stays pending", before: pullRequest(1, checks: .pending), after: pullRequest(1, checks: .pending), expected: []),
        Case(name: "pending to no checks", before: pullRequest(1, checks: .pending), after: pullRequest(1), expected: []),
        Case(name: "passing to failing", before: pullRequest(1, checks: .passing), after: pullRequest(1, checks: .failing), expected: []),
        Case(name: "failing to passing", before: pullRequest(1, checks: .failing), after: pullRequest(1, checks: .passing), expected: []),
        Case(name: "no checks to failing", before: pullRequest(1), after: pullRequest(1, checks: .failing), expected: []),
        Case(name: "review required to approved", before: pullRequest(1, reviewDecision: .reviewRequired), after: pullRequest(1, reviewDecision: .approved), expected: [.approved]),
        Case(name: "no decision to approved", before: pullRequest(1), after: pullRequest(1, reviewDecision: .approved), expected: [.approved]),
        Case(name: "approved to changes requested", before: pullRequest(1, reviewDecision: .approved), after: pullRequest(1, reviewDecision: .changesRequested), expected: [.changesRequested]),
        Case(name: "approved stays approved", before: pullRequest(1, reviewDecision: .approved), after: pullRequest(1, reviewDecision: .approved), expected: []),
        Case(name: "changes requested to review required", before: pullRequest(1, reviewDecision: .changesRequested), after: pullRequest(1, reviewDecision: .reviewRequired), expected: []),
        Case(name: "checks and review at once", before: pullRequest(1, reviewDecision: .reviewRequired, checks: .pending), after: pullRequest(1, reviewDecision: .approved, checks: .passing), expected: [.checksPassed, .approved]),
    ]

    @Test(arguments: cases)
    func comparesMyPullRequests(_ testCase: Case) {
        let changes = GitHubChanges.changes(from: GitHubSnapshot(mine: [testCase.before], reviewRequested: []), to: GitHubSnapshot(mine: [testCase.after], reviewRequested: []))
        #expect(changes.map(\.kind) == testCase.expected)
    }

    @Test func announcesNewReviewRequestsOnly() {
        let old = pullRequest(7, repository: "other/tool")
        let new = pullRequest(8, repository: "other/tool")
        let changes = GitHubChanges.changes(from: GitHubSnapshot(mine: [], reviewRequested: [old]), to: GitHubSnapshot(mine: [], reviewRequested: [new, old]))
        #expect(changes == [GitHubChange(kind: .reviewRequested, pullRequest: new)])
        #expect(GitHubChanges.changes(from: GitHubSnapshot(mine: [], reviewRequested: [old, new]), to: GitHubSnapshot(mine: [], reviewRequested: [old])).isEmpty)
    }

    @Test func ignoresNewlyOpenedPullRequestsOfMine() {
        let changes = GitHubChanges.changes(from: GitHubSnapshot(mine: [], reviewRequested: []), to: GitHubSnapshot(mine: [pullRequest(1, reviewDecision: .approved, checks: .failing)], reviewRequested: []))
        #expect(changes.isEmpty)
    }

    @Test func staysQuietForTheFirstSnapshot() {
        let current = GitHubSnapshot(mine: [pullRequest(1, checks: .failing)], reviewRequested: [pullRequest(9, repository: "other/tool")])
        #expect(GitHubChanges.changes(from: nil, to: current).isEmpty)
        #expect(GitHubChanges.announcement(from: nil, to: current) == nil)
    }

    @Test func formatsEveryKind() {
        let pullRequest = pullRequest(42, repository: "acme/app")
        let texts = [GitHubChange.Kind.checksFailed, .checksPassed, .approved, .changesRequested, .reviewRequested].map {
            GitHubChange(kind: $0, pullRequest: pullRequest).text
        }
        #expect(texts == ["app #42 checks failed", "app #42 checks passed", "app #42 approved", "app #42 changes requested", "Review requested: app #42"])
        let priorities = [GitHubChange.Kind.checksFailed, .checksPassed, .approved, .changesRequested, .reviewRequested].map {
            GitHubChange(kind: $0, pullRequest: pullRequest).priority
        }
        #expect(priorities == [.attention, .info, .info, .attention, .attention])
    }

    @Test func announcesASingleChange() throws {
        let announcement = try #require(GitHubChanges.announcement(for: [GitHubChange(kind: .approved, pullRequest: pullRequest(3))]))
        #expect(announcement.text == "app #3 approved")
        #expect(announcement.priority == .info)
        #expect(announcement.systemImage == "checkmark.seal.fill")
        #expect(GitHubChanges.announcement(for: []) == nil)
    }

    @Test func foldsSeveralChangesBehindTheMostImportant() throws {
        let changes = [
            GitHubChange(kind: .checksPassed, pullRequest: pullRequest(1)),
            GitHubChange(kind: .approved, pullRequest: pullRequest(2)),
            GitHubChange(kind: .changesRequested, pullRequest: pullRequest(3)),
            GitHubChange(kind: .reviewRequested, pullRequest: pullRequest(4, repository: "other/tool")),
        ]
        let announcement = try #require(GitHubChanges.announcement(for: changes))
        #expect(announcement.text == "app #3 changes requested and 3 more")
        #expect(announcement.priority == .attention)

        let info = try #require(GitHubChanges.announcement(for: Array(changes.prefix(2))))
        #expect(info.text == "app #1 checks passed and 1 more")
        #expect(info.priority == .info)
    }

    @Test func announcesChangesAcrossAFailedPoll() async throws {
        let suite = "GitHubChangesTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        defer { try? FileManager.default.removeItem(at: root) }

        let pending = GitHubSnapshot(mine: [pullRequest(1, checks: .pending)], reviewRequested: [])
        let failing = GitHubSnapshot(mine: [pullRequest(1, checks: .failing)], reviewRequested: [])
        let client = StubClient([.success(pending), .failure(.failed("down")), .success(failing)])
        let registry = PluginRegistry(storageRoot: root, userDefaults: defaults)
        let entry = try await registry.register(manifest: GitHubPlugin.manifest) {
            GitHubPlugin(context: $0, client: client, networkUpdates: networkNeverChanges)
        }
        let plugin = try #require(entry.plugin as? GitHubPlugin)
        let deadline = ContinuousClock.now + .seconds(5)
        func waitFor(_ condition: () -> Bool) async throws {
            while !condition() {
                try #require(ContinuousClock.now < deadline)
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        try await waitFor { plugin.controller.phase == .loaded(pending) }
        await plugin.controller.refresh()
        #expect(plugin.controller.phase == .failed("down"))
        await plugin.controller.refresh()
        #expect(plugin.controller.phase == .loaded(failing))
        try await waitFor { entry.context.announcement != nil }
        #expect(entry.context.announcement?.text == "app #1 checks failed")
        #expect(entry.context.announcement?.priority == .attention)
        await registry.setEnabled(false, for: GitHubPlugin.manifest.id)
    }
}
