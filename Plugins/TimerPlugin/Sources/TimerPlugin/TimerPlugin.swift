import AppKit
import IsletCore
import SwiftUI

@MainActor
public final class TimerPlugin: IsletPlugin {
    public static let manifest = PluginManifest(id: "islet.timer", displayName: "Timer", systemImage: "timer")
    static let contentWidth: CGFloat = 380
    static let contentPadding: CGFloat = 12
    static let sectionSpacing: CGFloat = 10
    static let controlRowHeight: CGFloat = 28
    static let stopwatchRowHeight: CGFloat = 32
    static let timerRowHeight: CGFloat = 32
    static let timerRowSpacing: CGFloat = 4
    static let maxVisibleTimerRows = 4
    static let presetMinutes = [1, 5, 10, 25]

    static func contentSize(timerCount: Int) -> CGSize {
        let controls = 2 * controlRowHeight + stopwatchRowHeight + 2 * sectionSpacing
        let list = timerCount > 0 ? sectionSpacing + timerListHeight(timerCount: timerCount) : 0
        return CGSize(width: contentWidth, height: 2 * contentPadding + controls + list)
    }

    static func timerListHeight(timerCount: Int) -> CGFloat {
        let rows = min(max(timerCount, 0), maxVisibleTimerRows)
        return CGFloat(rows) * timerRowHeight + CGFloat(max(rows - 1, 0)) * timerRowSpacing
    }

    let store: TimerStore

    public init(context: PluginContext) {
        let store = TimerStore(directory: context.storageDirectory, logger: context.logger)
        self.store = store
        store.onEvent = { [unowned context] event in
            switch event {
            case .ended(let label):
                NSSound(named: "Glass")?.play()
                context.announce(PillAnnouncement(text: "\(label) done", systemImage: "timer", tint: TimerStore.remainingTint, priority: .attention))
            case .missedEnd:
                context.announce(PillAnnouncement(text: "Timer ended", systemImage: "timer", tint: TimerStore.remainingTint, priority: .attention))
            }
        }
        context.derive(\.pillStatus) { store.pillStatus }
        context.derive(\.contentSize) { Self.contentSize(timerCount: store.timers.count) }
        context.observe({ [unowned context] in context.isScreenVisible }) { store.isScreenVisible = $0 }
    }

    public func activate() async throws {
        store.start()
    }

    public func deactivate() async {
        store.stop()
    }

    public func makeScreen() -> AnyView {
        AnyView(TimerScreen(store: store))
    }
}
