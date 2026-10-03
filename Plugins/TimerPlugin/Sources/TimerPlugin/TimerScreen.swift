import SwiftUI

struct TimerScreen: View {
    @Bindable var store: TimerStore
    @State private var customMinutes = 15

    var body: some View {
        VStack(spacing: TimerPlugin.sectionSpacing) {
            Picker("Mode", selection: $store.mode) {
                ForEach(TimerMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(height: TimerPlugin.pickerHeight)
            switch store.mode {
            case .timers:
                TimersSection(store: store, customMinutes: $customMinutes)
            case .pomodoro:
                PomodoroSection(store: store)
            case .stopwatch:
                StopwatchSection(store: store)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct RoundButtonStyle: ButtonStyle {
    let size: CGFloat
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(tint ?? Color.primary)
            .frame(width: size, height: size)
            .background(Circle().fill(.white.opacity(configuration.isPressed ? 0.26 : 0.14)))
            .contentShape(Circle())
    }
}

private struct CapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(Capsule().fill(.white.opacity(configuration.isPressed ? 0.26 : 0.14)))
            .contentShape(Capsule())
    }
}

private struct BigTime: View {
    let text: Text
    let tint: Color?

    var body: some View {
        text
            .font(.system(size: 40, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(tint ?? Color.primary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: TimerPlugin.timeHeight)
    }
}

private struct TimersSection: View {
    let store: TimerStore
    @Binding var customMinutes: Int

    var body: some View {
        VStack(spacing: TimerPlugin.sectionSpacing) {
            HStack(spacing: 5) {
                ForEach(TimerPlugin.presetMinutes, id: \.self) { minutes in
                    Button("\(minutes)m") { store.startTimer(minutes: minutes) }
                        .buttonStyle(CapsuleButtonStyle())
                }
                Spacer(minLength: 4)
                Button { customMinutes = max(customMinutes - 1, 1) } label: { Image(systemName: "minus") }
                    .buttonStyle(RoundButtonStyle(size: 24))
                Text("\(customMinutes) min")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .frame(minWidth: 44)
                    .fixedSize()
                Button { customMinutes = min(customMinutes + 1, 180) } label: { Image(systemName: "plus") }
                    .buttonStyle(RoundButtonStyle(size: 24))
                Button { store.startTimer(minutes: customMinutes) } label: { Image(systemName: "play.fill") }
                    .buttonStyle(RoundButtonStyle(size: TimerPlugin.newTimerHeight, tint: Color(TimerStore.remainingTint)))
                    .help("Start timer")
            }
            .frame(height: TimerPlugin.newTimerHeight)
            if !store.timers.isEmpty {
                ScrollView {
                    VStack(spacing: TimerPlugin.timerRowSpacing) {
                        ForEach(store.timers) { timer in
                            TimerRow(timer: timer, store: store)
                                .frame(height: TimerPlugin.timerRowHeight)
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(height: TimerPlugin.timerListHeight(timerCount: store.timers.count))
            }
        }
    }
}

private struct TimerRow: View {
    let timer: CountdownTimer
    let store: TimerStore

    var body: some View {
        HStack(spacing: 8) {
            Text(timer.label)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer()
            remaining
                .font(.system(size: 15, weight: .medium).monospacedDigit())
                .foregroundStyle(timer.isRunning ? Color(TimerStore.remainingTint) : Color.primary)
            Button {
                timer.isRunning ? store.pause(timer.id) : store.resume(timer.id)
            } label: {
                Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
            }
            .buttonStyle(RoundButtonStyle(size: 24))
            .help(timer.isRunning ? "Pause" : "Resume")
            Button {
                store.cancel(timer.id)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(RoundButtonStyle(size: 24))
            .help("Cancel")
        }
        .padding(.horizontal, 10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var remaining: some View {
        if let endDate = timer.endDate {
            Text(timerInterval: endDate.addingTimeInterval(-max(timer.duration, 0))...endDate, countsDown: true)
        } else {
            Text(TimerFormat.countdown(timer.remaining(at: .now)))
        }
    }
}

private struct StopwatchSection: View {
    let store: TimerStore

    private var isRunning: Bool {
        store.stopwatch.isRunning
    }

    var body: some View {
        VStack(spacing: TimerPlugin.sectionSpacing) {
            BigTime(text: elapsed, tint: isRunning ? Color(TimerStore.remainingTint) : nil)
            HStack(spacing: 16) {
                Button {
                    isRunning ? store.stopStopwatch() : store.startStopwatch()
                } label: {
                    Image(systemName: isRunning ? "pause.fill" : "play.fill")
                }
                .buttonStyle(RoundButtonStyle(size: TimerPlugin.primaryButtonSize))
                .help(isRunning ? "Stop" : "Start")
                Button {
                    store.resetStopwatch()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(RoundButtonStyle(size: TimerPlugin.secondaryButtonSize))
                .help("Reset")
                .disabled(!isRunning && store.stopwatch.accumulated == 0)
            }
            .frame(height: TimerPlugin.primaryButtonSize)
        }
    }

    private var elapsed: Text {
        if let startDate = store.stopwatch.startDate {
            Text(timerInterval: startDate.addingTimeInterval(-store.stopwatch.accumulated)...Date.distantFuture, countsDown: false)
        } else {
            Text(TimerFormat.elapsed(store.stopwatch.accumulated))
        }
    }
}

private struct PomodoroSection: View {
    let store: TimerStore

    private var state: PomodoroState? {
        store.pomodoro
    }

    private var isRunning: Bool {
        state?.isRunning == true
    }

    private var phase: PomodoroPhase {
        state?.phase ?? .work
    }

    private var tint: Color {
        Color(phase.isBreak ? TimerStore.breakTint : TimerStore.workTint)
    }

    var body: some View {
        VStack(spacing: TimerPlugin.sectionSpacing) {
            BigTime(text: remaining, tint: isRunning ? tint : nil)
            VStack(spacing: 4) {
                Text(phase.displayName)
                    .font(.system(size: 13, weight: .medium))
                HStack(spacing: 5) {
                    ForEach(0..<PomodoroSettings.workPhasesPerLongBreak, id: \.self) { index in
                        Circle()
                            .fill(index < (state?.completedWorkPhases ?? 0) ? AnyShapeStyle(Color(TimerStore.workTint)) : AnyShapeStyle(.white.opacity(0.2)))
                            .frame(width: TimerPlugin.pomodoroDotSize, height: TimerPlugin.pomodoroDotSize)
                    }
                }
            }
            .frame(height: TimerPlugin.pomodoroInfoHeight)
            HStack(spacing: 16) {
                Button {
                    isRunning ? store.pausePomodoro() : store.startPomodoro()
                } label: {
                    Image(systemName: isRunning ? "pause.fill" : "play.fill")
                }
                .buttonStyle(RoundButtonStyle(size: TimerPlugin.primaryButtonSize))
                .help(isRunning ? "Pause" : "Start")
                Button {
                    store.stopPomodoro()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(RoundButtonStyle(size: TimerPlugin.secondaryButtonSize))
                .help("Stop")
                .disabled(state == nil)
            }
            .frame(height: TimerPlugin.primaryButtonSize)
        }
    }

    private var remaining: Text {
        if let state, let endDate = state.endDate {
            Text(timerInterval: endDate.addingTimeInterval(-max(state.duration, 0))...endDate, countsDown: true)
        } else {
            Text(TimerFormat.countdown(state.map { $0.remaining ?? store.pomodoroSettings.duration(for: $0.phase) } ?? store.pomodoroSettings.duration(for: .work)))
        }
    }
}
