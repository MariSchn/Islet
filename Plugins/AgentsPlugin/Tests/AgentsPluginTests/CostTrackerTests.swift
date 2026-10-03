import Foundation
import Testing
@testable import AgentsPlugin

struct CostTrackerTests {
    @Test func accumulatesDeltasAndResetsAtMidnight() {
        let calendar = Calendar(identifier: .gregorian)
        var tracker = CostTracker(calendar: calendar)
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 9, minute: 0))!
        tracker.record(sessionID: "a", cost: 1, at: morning)
        tracker.record(sessionID: "a", cost: 1.5, at: morning)
        #expect(tracker.total(at: morning) == 1.5)
        tracker.record(sessionID: "a", cost: 1.25, at: morning)
        #expect(tracker.total(at: morning) == 1.5)
        tracker.record(sessionID: "b", cost: 2, at: morning)
        #expect(tracker.total(at: morning) == 3.5)

        let nextMorning = calendar.date(byAdding: .day, value: 1, to: morning)!
        #expect(tracker.total(at: nextMorning) == 0)
        tracker.record(sessionID: "a", cost: 2, at: nextMorning)
        #expect(tracker.total(at: nextMorning) == 0.5)
        tracker.record(sessionID: "c", cost: 4, at: nextMorning)
        #expect(tracker.total(at: nextMorning) == 4.5)
    }
}
