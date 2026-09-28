import CoreGraphics
import Foundation
import IsletCore
import Testing
@testable import ShelfPlugin

@MainActor
struct ShelfSizingTests {
    @Test func widthGrowsWithItemsBetweenBounds() {
        let height: CGFloat = 2 * 12 + 2 * 4 + 88
        #expect(ShelfPlugin.contentSize(forItemCount: 0) == CGSize(width: 360, height: height))
        #expect(ShelfPlugin.contentSize(forItemCount: 3) == CGSize(width: 360, height: height))
        #expect(ShelfPlugin.contentSize(forItemCount: 4) == CGSize(width: 2 * 12 + 2 * 4 + 4 * 84 + 3 * 8, height: height))
        #expect(ShelfPlugin.contentSize(forItemCount: 5) == CGSize(width: 2 * 12 + 2 * 4 + 5 * 84 + 4 * 8, height: height))
        #expect(ShelfPlugin.contentSize(forItemCount: 6) == CGSize(width: 520, height: height))
        #expect(ShelfPlugin.contentSize(forItemCount: 50) == CGSize(width: 520, height: height))
    }

    @Test func contentSizeFollowsTheItems() async throws {
        let suite = "ShelfSizingTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = PluginRegistry(storageRoot: root, userDefaults: defaults)
        let entry = try await registry.register(ShelfPlugin.self)
        let plugin = try #require(entry.plugin as? ShelfPlugin)
        #expect(entry.context.contentSize == ShelfPlugin.contentSize(forItemCount: 0))

        let files = try (0..<4).map { index in
            let file = root.appending(path: "\(index).txt")
            try Data("\(index)".utf8).write(to: file)
            return file
        }
        plugin.store.add(files)
        let deadline = ContinuousClock.now + .seconds(2)
        while entry.context.contentSize != ShelfPlugin.contentSize(forItemCount: 4) {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
    }
}
