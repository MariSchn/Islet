import Foundation
import IsletCore
import Testing
@testable import AgentsPlugin

@MainActor
struct DisplaySettingsControllerTests {
    private func makeController() -> AgentsController {
        let directory = FileManager.default.temporaryDirectory.appending(path: "DisplaySettingsControllerTests." + UUID().uuidString)
        let usage = UsageMonitor(isEnabled: true)
        usage.receive(ClaudeUsage(fiveHour: UsageWindow(utilization: 40, resetsAt: nil), sevenDay: UsageWindow(utilization: 10, resetsAt: nil)))
        return AgentsController(token: "t", home: directory, port: 0, alerts: .silent, showsUsage: true, usage: usage)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }

    @Test func settingsArePersistedAndRestored() async throws {
        let suite = "AgentsSettingsTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: FileManager.default.temporaryDirectory.appending(path: "\(suite)/defaults").path))
        defaults.set([AgentsPlugin.manifest.id], forKey: "islet.disabledPlugins")
        let storage = FileManager.default.temporaryDirectory.appending(path: suite, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: storage) }
        func makePlugin() async throws -> AgentsPlugin {
            let registry = PluginRegistry(storageRoot: storage, userDefaults: defaults)
            return try #require(try await registry.register(AgentsPlugin.self).plugin as? AgentsPlugin)
        }

        let first = try await makePlugin()
        first.controller.display.historyLength = 3
        first.controller.display.pillContent = .summary
        first.controller.display.showsResetTimes = false
        first.controller.alerts.finishedSound = false
        try await waitUntil { defaults.integer(forKey: "plugin.\(AgentsPlugin.manifest.id).historyLength") == 3 && defaults.object(forKey: "plugin.\(AgentsPlugin.manifest.id).finishedSound") as? Bool == false }

        let restored = try await makePlugin()
        #expect(restored.controller.display.historyLength == 3)
        #expect(restored.controller.display.pillContent == .summary)
        #expect(!restored.controller.display.showsResetTimes)
        #expect(!restored.controller.alerts.finishedSound)
        #expect(restored.controller.alerts.attentionSound)
    }

    @Test func aWindowMissingFromAReportCountsAsUnused() {
        let monitor = UsageMonitor(isEnabled: true)
        let weekly = UsageWindow(utilization: 41, resetsAt: nil)
        monitor.receive(ClaudeUsage(fiveHour: nil, sevenDay: weekly))
        #expect(monitor.usage == ClaudeUsage(fiveHour: .unused, sevenDay: weekly))
    }

    @Test func hidingBothLimitsRemovesTheUsageBar() async throws {
        let controller = makeController()
        #expect(controller.showsUsageBar)
        let withBar = AgentsPlugin.contentSize(for: [], expanded: [], showsUsage: controller.showsUsageBar, historyLength: 8).height

        controller.display.showsFiveHourLimit = false
        #expect(controller.visibleUsage?.fiveHour == nil)
        #expect(controller.showsUsageBar)

        controller.display.showsWeeklyLimit = false
        #expect(!controller.showsUsageBar)
        let withoutBar = AgentsPlugin.contentSize(for: [], expanded: [], showsUsage: controller.showsUsageBar, historyLength: 8).height
        #expect(withBar - withoutBar == AgentsPlugin.usageBarHeight + AgentsPlugin.rowSpacing)
    }

    @Test func finishedAnnouncementsFollowTheFinishedPillSetting() {
        let controller = makeController()
        let finished = PillAnnouncement(text: "a finished", systemImage: "checkmark.circle.fill", tint: SessionColors.finishedTint)
        let attention = PillAnnouncement(text: "a · Has a question", systemImage: "exclamationmark.circle.fill", tint: SessionColors.attentionTint, priority: .attention)
        #expect(controller.shouldAnnounce(finished))

        controller.display.pillShowsFinished = false
        #expect(!controller.shouldAnnounce(finished))
        #expect(controller.shouldAnnounce(attention))

        controller.alerts.announcesInNotch = false
        #expect(!controller.shouldAnnounce(attention))
    }
}
