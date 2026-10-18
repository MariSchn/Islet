import Foundation
import IsletCore
import Testing
@testable import DownloadsPlugin

@MainActor
struct DownloadsPluginTests {
    @Test func derivesThePillAndRecentListFromTheFolder() async throws {
        let suite = "DownloadsPluginTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: FileManager.default.temporaryDirectory.appending(path: "\(suite)/defaults").path))
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "Downloads")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let registry = PluginRegistry(storageRoot: root.appending(path: "Plugins"), userDefaults: defaults)
        let entry = try await registry.register(manifest: DownloadsPlugin.manifest) { DownloadsPlugin(context: $0, folder: folder) }
        let plugin = try #require(entry.plugin as? DownloadsPlugin)
        #expect(entry.state.isActive)

        let deadline = ContinuousClock.now + .seconds(10)
        while entry.context.contentSize != DownloadsPlugin.contentSize(activeCount: 0, recentCount: 0, accessDenied: false) || plugin.monitor.scanCount == 0 {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(entry.context.pillStatus == nil)

        let partial = folder.appending(path: "report.pdf.crdownload")
        try Data(count: 2048).write(to: partial)
        let expectedText = "report.pdf · \(DownloadsPlugin.formatted(bytes: 2048))"
        while entry.context.pillStatus?.text != expectedText {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }

        try FileManager.default.moveItem(at: partial, to: folder.appending(path: "report.pdf"))
        while entry.context.pillStatus != nil || plugin.recent.items.first?.name != "report.pdf" {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }
        while entry.context.announcement?.text != "report.pdf downloaded" {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }
        while entry.context.contentSize != DownloadsPlugin.contentSize(activeCount: 0, recentCount: 1, accessDenied: false) {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }

        await registry.setEnabled(false, for: DownloadsPlugin.manifest.id)
        #expect(entry.context.pillStatus == nil)
    }
}
