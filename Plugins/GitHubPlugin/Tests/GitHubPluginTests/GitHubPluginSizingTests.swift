import Foundation
import IsletCore
import Testing
@testable import GitHubPlugin

@MainActor
struct GitHubPluginSizingTests {
    @Test func messagesUseAFixedHeight() {
        let message = CGSize(width: 480, height: 2 * 12 + 96)
        #expect(GitHubPlugin.contentSize(for: nil) == message)
        #expect(GitHubPlugin.contentSize(for: snapshot(mine: 0, review: 0)) == message)
    }

    @Test func listsGrowWithRowsAndSections() {
        #expect(GitHubPlugin.contentSize(for: snapshot(mine: 1, review: 0)) == CGSize(width: 480, height: 2 * 12 + 18 + 40))
        #expect(GitHubPlugin.contentSize(for: snapshot(mine: 0, review: 2)) == CGSize(width: 480, height: 2 * 12 + 18 + 2 * 40))
        #expect(GitHubPlugin.contentSize(for: snapshot(mine: 2, review: 1)) == CGSize(width: 480, height: 2 * 12 + 2 * 18 + 8 + 3 * 40))
    }

    @Test func showsAtMostSixRows() {
        let six = GitHubPlugin.contentSize(for: snapshot(mine: 3, review: 3))
        #expect(six == CGSize(width: 480, height: 2 * 12 + 2 * 18 + 8 + 6 * 40))
        #expect(GitHubPlugin.contentSize(for: snapshot(mine: 20, review: 20)) == six)
        #expect(GitHubPlugin.contentSize(for: snapshot(mine: 20, review: 0)) == CGSize(width: 480, height: 2 * 12 + 18 + 6 * 40))
    }

    @Test func derivedSizeFollowsTheFetchedPullRequests() async throws {
        let suite = "GitHubPluginSizingTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        defer { try? FileManager.default.removeItem(at: root) }

        let client = StubClient([.success(snapshot(mine: 2, review: 1))])
        let registry = PluginRegistry(storageRoot: root, userDefaults: defaults)
        let entry = try await registry.register(manifest: GitHubPlugin.manifest) {
            GitHubPlugin(context: $0, client: client, networkUpdates: networkNeverChanges)
        }
        #expect(entry.state.isActive)
        #expect(entry.plugin is GitHubPlugin)

        let deadline = ContinuousClock.now + .seconds(5)
        while entry.context.contentSize != GitHubPlugin.contentSize(for: snapshot(mine: 2, review: 1)) {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(5))
        }
        await registry.setEnabled(false, for: GitHubPlugin.manifest.id)
    }
}
