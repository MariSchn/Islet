import AppKit
import IsletCore
import SwiftUI

@MainActor
public final class TimerPlugin: IsletPlugin {
    public static let manifest = PluginManifest(id: "islet.timer", displayName: "Timer", systemImage: "timer")
    static let contentWidth: CGFloat = 380
    static let contentPadding: CGFloat = 12
    static let sectionSpacing: CGFloat = 10
    static let pomodoroHeight: CGFloat = 44
    static let pomodoroDotSize: CGFloat = 6
    static let controlRowHeight: CGFloat = 28
    static let stopwatchRowHeight: CGFloat = 32
    static let timerRowHeight: CGFloat = 32
    static let timerRowSpacing: CGFloat = 4
    static let maxVisibleTimerRows = 4
    static let presetMinutes = [1, 5, 10, 25]

    static func contentSize(timerCount: Int) -> CGSize {
        let controls = pomodoroHeight + 2 * controlRowHeight + stopwatchRowHeight + 3 * sectionSpacing
        let list = timerCount > 0 ? sectionSpacing + timerListHeight(timerCount: timerCount) : 0
        return CGSize(width: contentWidth, height: 2 * contentPadding + controls + list)
    }

    static func timerListHeight(timerCount: Int) -> CGFloat {
        let rows = min(max(timerCount, 0), maxVisibleTimerRows)
        return CGFloat(rows) * timerRowHeight + CGFloat(max(rows - 1, 0)) * timerRowSpacing
    }

    static let pomodoroMinuteKeys: [(key: String, value: WritableKeyPath<PomodoroSettings, Int>, range: ClosedRange<Int>)] = [
        ("pomodoroWorkMinutes", \.workMinutes, 1...120),
        ("pomodoroShortBreakMinutes", \.shortBreakMinutes, 1...60),
        ("pomodoroLongBreakMinutes", \.longBreakMinutes, 1...60)
    ]
    static let pomodoroAutoStartKey = "pomodoroStartsNextPhaseAutomatically"

    let store: TimerStore

    public init(context: PluginContext) {
        let settings = context.settings
        let store = TimerStore(directory: context.storageDirectory, pomodoroSettings: Self.loadPomodoroSettings(from: settings), logger: context.logger)
        self.store = store
        store.onEvent = { [unowned context] event in
            switch event {
            case .ended(let label):
                NSSound(named: "Glass")?.play()
                context.announce(PillAnnouncement(text: "\(label) done", systemImage: "timer", tint: TimerStore.remainingTint, priority: .attention))
            case .missedEnd:
                context.announce(PillAnnouncement(text: "Timer ended", systemImage: "timer", tint: TimerStore.remainingTint, priority: .attention))
            case .phaseEnded(let next):
                NSSound(named: "Glass")?.play()
                context.announce(Self.announcement(for: next))
            case .missedPhaseEnd(let next):
                context.announce(Self.announcement(for: next))
            }
        }
        context.observe({ store.pomodoroSettings }) { pomodoro in
            for entry in Self.pomodoroMinuteKeys {
                settings.set(pomodoro[keyPath: entry.value], forKey: entry.key)
            }
            settings.set(pomodoro.startsNextPhaseAutomatically, forKey: Self.pomodoroAutoStartKey)
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

    public func makeSettingsView() -> AnyView? {
        AnyView(TimerSettings(store: store))
    }

    static func loadPomodoroSettings(from settings: PluginSettings) -> PomodoroSettings {
        var loaded = pomodoroMinuteKeys.reduce(into: PomodoroSettings()) { loaded, entry in
            let stored: Int = settings.value(forKey: entry.key) ?? loaded[keyPath: entry.value]
            loaded[keyPath: entry.value] = min(max(stored, entry.range.lowerBound), entry.range.upperBound)
        }
        loaded.startsNextPhaseAutomatically = settings.value(forKey: pomodoroAutoStartKey) ?? loaded.startsNextPhaseAutomatically
        return loaded
    }

    static func announcement(for next: PomodoroPhase) -> PillAnnouncement {
        PillAnnouncement(
            text: next.isBreak ? "Time for a break" : "Back to work",
            systemImage: "timer",
            tint: next.isBreak ? TimerStore.breakTint : TimerStore.workTint,
            priority: .attention
        )
    }
}

private struct TimerSettings: View {
    @Bindable var store: TimerStore

    var body: some View {
        Form {
            Section {
                Stepper("Work: \(store.pomodoroSettings.workMinutes) min", value: $store.pomodoroSettings.workMinutes, in: 1...120)
                Stepper("Short break: \(store.pomodoroSettings.shortBreakMinutes) min", value: $store.pomodoroSettings.shortBreakMinutes, in: 1...60)
                Stepper("Long break: \(store.pomodoroSettings.longBreakMinutes) min", value: $store.pomodoroSettings.longBreakMinutes, in: 1...60)
                Toggle("Start the next phase automatically", isOn: $store.pomodoroSettings.startsNextPhaseAutomatically)
            } header: {
                Text("Pomodoro")
            } footer: {
                Text("A long break follows every \(PomodoroSettings.workPhasesPerLongBreak) work phases. New durations apply from the next phase.")
            }
        }
    }
}
