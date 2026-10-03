import Foundation
import Testing
@testable import GitHubPlugin

struct PollScheduleTests {
    @Test func backoffDoublesFromOneMinuteUpToFifteen() {
        let minutes = (1...7).map { PollSchedule.backoff(afterFailures: $0) / .seconds(60) }
        #expect(minutes == [1, 2, 4, 8, 15, 15, 15])
        #expect(PollSchedule.backoff(afterFailures: 0) == .zero)
    }

    @Test func pollsFasterWhileTheScreenIsVisible() {
        #expect(PollSchedule.interval(isScreenVisible: false, failures: 0) == .seconds(120))
        #expect(PollSchedule.interval(isScreenVisible: true, failures: 0) == .seconds(60))
    }

    @Test func backsOffAfterFailuresWhetherVisibleOrNot() {
        #expect(PollSchedule.interval(isScreenVisible: true, failures: 1) == .seconds(60))
        #expect(PollSchedule.interval(isScreenVisible: false, failures: 2) == .seconds(120))
        #expect(PollSchedule.interval(isScreenVisible: true, failures: 3) == .seconds(240))
        #expect(PollSchedule.interval(isScreenVisible: false, failures: 4) == .seconds(480))
        #expect(PollSchedule.interval(isScreenVisible: true, failures: 9) == .seconds(900))
    }

    @Test func refreshesRightAwayWhenTheLastFetchIsStale() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(PollSchedule.delayBeforeRefresh(lastFetch: nil, now: now, isScreenVisible: true, failures: 0) == .zero)
        #expect(PollSchedule.delayBeforeRefresh(lastFetch: now - 30, now: now, isScreenVisible: true, failures: 0) == .zero)
        #expect(PollSchedule.delayBeforeRefresh(lastFetch: now - 300, now: now, isScreenVisible: true, failures: 3) == .zero)
    }

    @Test func waitsOutTheRestOfTheIntervalAfterARecentFetch() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(PollSchedule.delayBeforeRefresh(lastFetch: now - 10, now: now, isScreenVisible: true, failures: 0) == .seconds(50))
        #expect(PollSchedule.delayBeforeRefresh(lastFetch: now - 10, now: now, isScreenVisible: false, failures: 0) == .seconds(110))
        #expect(PollSchedule.delayBeforeRefresh(lastFetch: now - 20, now: now, isScreenVisible: true, failures: 2) == .seconds(100))
    }
}
