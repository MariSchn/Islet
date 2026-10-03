import Foundation

enum PollSchedule {
    static let activeInterval: Duration = .seconds(120)
    static let visibleInterval: Duration = .seconds(60)
    static let staleAge: Duration = .seconds(30)
    static let backoffSteps: [Duration] = [.seconds(60), .seconds(120), .seconds(240), .seconds(480)]
    static let maxBackoff: Duration = .seconds(900)

    static func backoff(afterFailures failures: Int) -> Duration {
        guard failures > 0 else { return .zero }
        return failures <= backoffSteps.count ? backoffSteps[failures - 1] : maxBackoff
    }

    static func interval(isScreenVisible: Bool, failures: Int) -> Duration {
        if failures > 0 { return backoff(afterFailures: failures) }
        return isScreenVisible ? visibleInterval : activeInterval
    }

    static func delayBeforeRefresh(lastFetch: Date?, now: Date, isScreenVisible: Bool, failures: Int) -> Duration {
        guard let lastFetch else { return .zero }
        let age = Duration.seconds(max(0, now.timeIntervalSince(lastFetch)))
        guard age < staleAge else { return .zero }
        return max(.zero, interval(isScreenVisible: isScreenVisible, failures: failures) - age)
    }
}
