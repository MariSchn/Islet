import Foundation
import IsletCore
import Testing
@testable import GitHubPlugin

@MainActor
struct GitHubPillTests {
    private func segments(_ failing: Double, _ pending: Double, _ passing: Double) -> [PillStatus.Ring.Segment] {
        [
            .init(value: failing, tint: GitHubPill.failingTint),
            .init(value: pending, tint: GitHubPill.pendingTint),
            .init(value: passing, tint: GitHubPill.passingTint),
        ].filter { $0.value > 0 }
    }

    @Test func allPassingIsAmbient() throws {
        let pill = try #require(GitHubPill.status(for: GitHubSnapshot(mine: [pullRequest(1, checks: .passing), pullRequest(2, checks: .passing)], reviewRequested: [])))
        #expect(pill.priority == .ambient)
        #expect(pill.text == "2 PRs")
        #expect(pill.systemImage == "arrow.triangle.pull")
        #expect(pill.ring?.segments == segments(0, 0, 2))
    }

    @Test func oneFailingNeedsAttention() throws {
        let mine = [pullRequest(1, checks: .failing), pullRequest(2, checks: .pending), pullRequest(3, checks: .passing), pullRequest(4, checks: .passing), pullRequest(5)]
        let pill = try #require(GitHubPill.status(for: GitHubSnapshot(mine: mine, reviewRequested: [])))
        #expect(pill.priority == .attention)
        #expect(pill.text == "5 PRs")
        #expect(pill.ring?.segments == segments(1, 1, 2))
    }

    @Test func aReviewRequestNeedsAttention() throws {
        let pill = try #require(GitHubPill.status(for: GitHubSnapshot(mine: [pullRequest(1, checks: .passing)], reviewRequested: [pullRequest(9, repository: "other/tool")])))
        #expect(pill.priority == .attention)
        #expect(pill.text == "2 PRs")
        #expect(pill.ring?.segments == segments(0, 0, 1))

        let reviewOnly = try #require(GitHubPill.status(for: GitHubSnapshot(mine: [], reviewRequested: [pullRequest(9, repository: "other/tool")])))
        #expect(reviewOnly.priority == .attention)
        #expect(reviewOnly.text == "1 PR")
        #expect(reviewOnly.ring == nil)
    }

    @Test func pendingAloneStaysAmbient() throws {
        let pill = try #require(GitHubPill.status(for: GitHubSnapshot(mine: [pullRequest(1, checks: .pending)], reviewRequested: [])))
        #expect(pill.priority == .ambient)
        #expect(pill.ring?.segments == segments(0, 1, 0))
    }

    @Test func pullRequestsWithoutChecksShowTextOnly() throws {
        let pill = try #require(GitHubPill.status(for: GitHubSnapshot(mine: [pullRequest(1), pullRequest(2)], reviewRequested: [])))
        #expect(pill.priority == .ambient)
        #expect(pill.ring == nil)
    }

    @Test func noPullRequestsMeansNoPill() {
        #expect(GitHubPill.status(for: GitHubSnapshot(mine: [], reviewRequested: [])) == nil)
    }

    @Test func controllerHidesThePillWhenTurnedOffOrNotLoaded() async {
        let controller = GitHubController(client: StubClient([.success(GitHubSnapshot(mine: [pullRequest(1, checks: .failing)], reviewRequested: []))]), networkUpdates: networkNeverChanges)
        #expect(controller.pillStatus == nil)
        await controller.refresh()
        #expect(controller.pillStatus?.priority == .attention)
        controller.showsPill = false
        #expect(controller.pillStatus == nil)
    }

    @Test func derivesThePillAndSavesTheSetting() async throws {
        let suite = "GitHubPillTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        defer { try? FileManager.default.removeItem(at: root) }

        let client = StubClient([.success(GitHubSnapshot(mine: [pullRequest(1, checks: .failing)], reviewRequested: []))])
        let registry = PluginRegistry(storageRoot: root, userDefaults: defaults)
        let entry = try await registry.register(manifest: GitHubPlugin.manifest) {
            GitHubPlugin(context: $0, client: client, networkUpdates: networkNeverChanges)
        }
        let plugin = try #require(entry.plugin as? GitHubPlugin)
        let deadline = ContinuousClock.now + .seconds(5)
        while entry.context.pillStatus?.priority != .attention {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(5))
        }
        let key = "plugin.\(GitHubPlugin.manifest.id).\(GitHubPlugin.showsPillKey)"
        #expect(defaults.object(forKey: key) == nil)

        plugin.controller.showsPill = false
        while entry.context.pillStatus != nil || defaults.object(forKey: key) == nil {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(defaults.bool(forKey: key) == false)
        await registry.setEnabled(false, for: GitHubPlugin.manifest.id)
    }
}
