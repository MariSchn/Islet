import SwiftUI

struct TimerScreen: View {
    let store: TimerStore
    @State private var customMinutes = 15

    var body: some View {
        VStack(spacing: TimerPlugin.sectionSpacing) {
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
