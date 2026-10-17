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

    @Test func baselinesAreForgottenADayAfterTheLastReport() {
        let calendar = Calendar(identifier: .gregorian)
        var tracker = CostTracker(calendar: calendar)
        let monday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9, minute: 0))!
        tracker.record(sessionID: "a", cost: 5, at: monday)
        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday)!
        tracker.record(sessionID: "a", cost: 6, at: tuesday)
        #expect(tracker.total(at: tuesday) == 1)

        let thursday = calendar.date(byAdding: .day, value: 2, to: tuesday)!
        tracker.record(sessionID: "a", cost: 7, at: thursday, sessionDuration: .seconds(3 * 24 * 3600))
        #expect(tracker.total(at: thursday) == 0)
    }

    @Test func decodesTrackersSavedWithoutReportDates() throws {
        var tracker = try JSONDecoder().decode(CostTracker.self, from: Data(#"{"lastCost":{"a":2},"accumulated":2}"#.utf8))
        #expect(tracker.total(at: .now) == 2)
        tracker.record(sessionID: "a", cost: 3, at: .now)
        #expect(tracker.total(at: .now) == 3)
    }

    @Test func sessionsFromBeforeTodayOnlyCountWhatTheySpendToday() {
        let calendar = Calendar(identifier: .gregorian)
        var tracker = CostTracker(calendar: calendar)
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 9, minute: 0))!
        tracker.record(sessionID: "old", cost: 42, at: morning, sessionDuration: .seconds(12 * 3600))
        #expect(tracker.total(at: morning) == 0)
        tracker.record(sessionID: "old", cost: 43, at: morning, sessionDuration: .seconds(12 * 3600 + 60))
        #expect(tracker.total(at: morning) == 1)
        tracker.record(sessionID: "today", cost: 5, at: morning, sessionDuration: .seconds(3600))
        #expect(tracker.total(at: morning) == 6)
    }
}
