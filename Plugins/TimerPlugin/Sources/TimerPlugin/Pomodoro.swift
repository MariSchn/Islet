import Foundation

enum PomodoroPhase: String, Codable, Equatable {
    case work
    case shortBreak
    case longBreak

    var displayName: String {
        switch self {
        case .work: "Work"
        case .shortBreak: "Short break"
        case .longBreak: "Long break"
        }
    }

    var isBreak: Bool {
        self != .work
    }
}

struct PomodoroSettings: Equatable {
    static let workPhasesPerLongBreak = 4

    var workMinutes = 25
    var shortBreakMinutes = 5
    var longBreakMinutes = 15
    var startsNextPhaseAutomatically = false

    func duration(for phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .work: TimeInterval(workMinutes) * 60
        case .shortBreak: TimeInterval(shortBreakMinutes) * 60
        case .longBreak: TimeInterval(longBreakMinutes) * 60
        }
    }
}

struct PomodoroState: Codable, Equatable {
    var phase: PomodoroPhase
    var completedWorkPhases: Int
    var duration: TimeInterval
    var endDate: Date?
    var remaining: TimeInterval?

    var isRunning: Bool {
        endDate != nil
    }

    func remaining(at now: Date) -> TimeInterval {
        if let endDate {
            return max(endDate.timeIntervalSince(now), 0)
        }
        return remaining ?? duration
    }

    func next(settings: PomodoroSettings) -> PomodoroState {
        var completed = completedWorkPhases
        let nextPhase: PomodoroPhase
        switch phase {
        case .work:
            completed += 1
            nextPhase = completed >= PomodoroSettings.workPhasesPerLongBreak ? .longBreak : .shortBreak
        case .shortBreak:
            nextPhase = .work
        case .longBreak:
            completed = 0
            nextPhase = .work
        }
        return PomodoroState(phase: nextPhase, completedWorkPhases: completed, duration: settings.duration(for: nextPhase))
    }
}
