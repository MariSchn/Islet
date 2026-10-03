import SwiftUI

struct TimerScreen: View {
    let store: TimerStore
    @State private var customMinutes = 15

    var body: some View {
        VStack(spacing: TimerPlugin.sectionSpacing) {
            PomodoroSection(store: store)
                .frame(height: TimerPlugin.pomodoroHeight)
            HStack(spacing: 8) {
                ForEach(TimerPlugin.presetMinutes, id: \.self) { minutes in
                    Button {
                        store.startTimer(minutes: minutes)
                    } label: {
                        Text("\(minutes) min")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .buttonStyle(.bordered)
            .frame(height: TimerPlugin.controlRowHeight)
            HStack(spacing: 8) {
                Stepper(value: $customMinutes, in: 1...180) {
                    Text("\(customMinutes) min")
                        .monospacedDigit()
                }
                Spacer()
                Button("Start") { store.startTimer(minutes: customMinutes) }
                    .buttonStyle(.bordered)
            }
            .frame(height: TimerPlugin.controlRowHeight)
            StopwatchRow(store: store)
                .frame(height: TimerPlugin.stopwatchRowHeight)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct TimerRow: View {
    static let reference = Date(timeIntervalSinceReferenceDate: 0)

    let timer: CountdownTimer
    let store: TimerStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .foregroundStyle(timer.isRunning ? .orange : .secondary)
            Text(timer.label)
                .lineLimit(1)
            Spacer()
            remaining
                .font(.system(size: 15, weight: .medium).monospacedDigit())
            Button {
                timer.isRunning ? store.pause(timer.id) : store.resume(timer.id)
            } label: {
                Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
            }
            .help(timer.isRunning ? "Pause" : "Resume")
            Button {
                store.cancel(timer.id)
            } label: {
                Image(systemName: "xmark")
            }
            .help("Cancel")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var remaining: some View {
        if let endDate = timer.endDate {
            Text(timerInterval: endDate.addingTimeInterval(-max(timer.duration, 0))...endDate, countsDown: true)
        } else {
            Text(timerInterval: Self.reference...Self.reference.addingTimeInterval(timer.remaining(at: .now)), pauseTime: Self.reference, countsDown: true)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StopwatchRow: View {
    let store: TimerStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "stopwatch")
                .foregroundStyle(store.stopwatch.isRunning ? .orange : .secondary)
            Text("Stopwatch")
            Spacer()
            elapsed
                .font(.system(size: 15, weight: .medium).monospacedDigit())
            Button {
                store.stopwatch.isRunning ? store.stopStopwatch() : store.startStopwatch()
            } label: {
                Image(systemName: store.stopwatch.isRunning ? "pause.fill" : "play.fill")
            }
            .help(store.stopwatch.isRunning ? "Stop" : "Start")
            Button {
                store.resetStopwatch()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .help("Reset")
            .disabled(!store.stopwatch.isRunning && store.stopwatch.accumulated == 0)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var elapsed: some View {
        if let startDate = store.stopwatch.startDate {
            Text(timerInterval: startDate.addingTimeInterval(-store.stopwatch.accumulated)...Date.distantFuture, countsDown: false)
        } else {
            Text(timerInterval: TimerRow.reference...Date.distantFuture, pauseTime: TimerRow.reference.addingTimeInterval(store.stopwatch.accumulated), countsDown: false)
                .foregroundStyle(store.stopwatch.accumulated > 0 ? .primary : .secondary)
        }
    }
}

private struct PomodoroSection: View {
    let store: TimerStore

    private var state: PomodoroState? {
        store.pomodoro
    }

    private var phase: PomodoroPhase {
        state?.phase ?? .work
    }

    private var tint: Color {
        Color(phase.isBreak ? TimerStore.breakTint : TimerStore.workTint)
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(phase.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(state == nil ? .secondary : .primary)
                HStack(spacing: 4) {
                    ForEach(0..<PomodoroSettings.workPhasesPerLongBreak, id: \.self) { index in
                        Circle()
                            .fill(index < (state?.completedWorkPhases ?? 0) ? AnyShapeStyle(Color(TimerStore.workTint)) : AnyShapeStyle(.white.opacity(0.2)))
                            .frame(width: TimerPlugin.pomodoroDotSize, height: TimerPlugin.pomodoroDotSize)
                    }
                }
            }
            Spacer()
            remaining
                .font(.system(size: 22, weight: .medium).monospacedDigit())
                .foregroundStyle(state?.isRunning == true ? tint : .secondary)
            Button {
                state?.isRunning == true ? store.pausePomodoro() : store.startPomodoro()
            } label: {
                Image(systemName: state?.isRunning == true ? "pause.fill" : "play.fill")
            }
            .help(state?.isRunning == true ? "Pause" : "Start")
            Button {
                store.stopPomodoro()
            } label: {
                Image(systemName: "stop.fill")
            }
            .help("Stop")
            .disabled(state == nil)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var remaining: some View {
        if let state, let endDate = state.endDate {
            Text(timerInterval: endDate.addingTimeInterval(-max(state.duration, 0))...endDate, countsDown: true)
        } else {
            let seconds = state.map { $0.remaining ?? store.pomodoroSettings.duration(for: $0.phase) } ?? store.pomodoroSettings.duration(for: .work)
            Text(timerInterval: TimerRow.reference...TimerRow.reference.addingTimeInterval(seconds), pauseTime: TimerRow.reference, countsDown: true)
        }
    }
}
