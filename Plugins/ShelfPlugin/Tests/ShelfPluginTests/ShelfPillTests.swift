import Foundation
import IsletCore
import Testing
@testable import ShelfPlugin

@MainActor
struct ShelfPillTests {
    @Test func countPillTextUsesTheItemCount() {
        #expect(ShelfPlugin.countPill(itemCount: 0, showsCount: true) == nil)
        #expect(ShelfPlugin.countPill(itemCount: 3, showsCount: false) == nil)
        let one = ShelfPlugin.countPill(itemCount: 1, showsCount: true)
        #expect(one?.text == "1 item")
        #expect(one?.systemImage == "tray.full")
        #expect(one?.priority == .ambient)
        #expect(ShelfPlugin.countPill(itemCount: 3, showsCount: true)?.text == "3 items")
    }

    @Test func countPillFollowsItemsWhenEnabled() async throws {
        let harness = try await Harness()
        defer { harness.cleanup() }
        harness.plugin.store.showsCountPill = true
        let files = try harness.writeFiles(count: 3)
        await harness.plugin.store.add(files)

        let deadline = ContinuousClock.now + .seconds(2)
        let expected = ShelfPlugin.countPill(itemCount: 3, showsCount: true)
        while harness.entry.context.pillStatus != expected {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }

        harness.plugin.store.removeAll()
        while harness.entry.context.pillStatus != nil {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
    }

    @Test func countPillStaysHiddenWhenTheSettingIsOff() async throws {
        let harness = try await Harness()
        defer { harness.cleanup() }
        let stored: Bool? = harness.entry.context.settings.value(forKey: ShelfPlugin.showsCountPillKey)
        #expect(harness.plugin.store.showsCountPill == false)
        #expect(stored == nil)

        let files = try harness.writeFiles(count: 2)
        await harness.plugin.store.add(files)
        let deadline = ContinuousClock.now + .seconds(2)
        while harness.entry.context.contentSize != ShelfPlugin.contentSize(forItemCount: 2) {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
        #expect(harness.entry.context.pillStatus == nil)
    }
}

@MainActor
private final class Harness {
    let suite: String
    let defaults: UserDefaults
    let root: URL
    let registry: PluginRegistry
    let entry: PluginEntry
    let plugin: ShelfPlugin

    init() async throws {
        suite = "ShelfPillTests." + UUID().uuidString
        defaults = try #require(UserDefaults(suiteName: suite))
        root = FileManager.default.temporaryDirectory.appending(path: suite)
        registry = PluginRegistry(storageRoot: root, userDefaults: defaults)
        entry = try await registry.register(ShelfPlugin.self)
        plugin = try #require(entry.plugin as? ShelfPlugin)
    }

    func writeFiles(count: Int) throws -> [URL] {
        try (0..<count).map { index in
            let file = root.appending(path: "\(index).txt")
            try Data("\(index)".utf8).write(to: file)
            return file
        }
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}
