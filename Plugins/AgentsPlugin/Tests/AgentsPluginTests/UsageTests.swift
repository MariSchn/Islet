import Foundation
import IsletCore
import Testing
@testable import AgentsPlugin

struct UsageTests {
    @Test func decodesTheStatusLineInput() throws {
        let update = try StatusLineUpdate.decode(Data(#"{"session_id":"s1","session_name":"islet main","rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600},"seven_day":{"used_percentage":41,"resets_at":1738857600}},"model":{"id":"claude-opus-5-5"}}"#.utf8))
        #expect(update.sessionID == "s1")
        #expect(update.sessionName == "islet main")
        #expect(update.usage == ClaudeUsage(
            fiveHour: UsageWindow(utilization: 23.5, resetsAt: Date(timeIntervalSince1970: 1_738_425_600)),
            sevenDay: UsageWindow(utilization: 41, resetsAt: Date(timeIntervalSince1970: 1_738_857_600))
        ))

        let partial = try StatusLineUpdate.decode(Data(#"{"session_id":"s1","session_name":"","rate_limits":{"seven_day":{"used_percentage":2}}}"#.utf8))
        #expect(partial.sessionName == nil)
        #expect(partial.usage == ClaudeUsage(fiveHour: nil, sevenDay: UsageWindow(utilization: 2, resetsAt: nil)))

        #expect(try StatusLineUpdate.decode(Data(#"{"session_id":"s1"}"#.utf8)).usage == nil)
        #expect(throws: (any Error).self) { try StatusLineUpdate.decode(Data(#"{"session_name":"x"}"#.utf8)) }
        #expect(throws: (any Error).self) { try StatusLineUpdate.decode(Data("[]".utf8)) }
    }

    @Test func hiddenLimitsAreDroppedAndTheBarDisappearsWithoutAny() {
        let usage = ClaudeUsage(fiveHour: UsageWindow(utilization: 10, resetsAt: nil), sevenDay: UsageWindow(utilization: 50, resetsAt: nil))
        var display = DisplaySettings()
        #expect(display.visibleUsage(usage) == usage)
        display.showsFiveHourLimit = false
        #expect(display.visibleUsage(usage) == ClaudeUsage(fiveHour: nil, sevenDay: usage.sevenDay))
        display.showsWeeklyLimit = false
        #expect(display.visibleUsage(usage) == nil)
        display.showsFiveHourLimit = true
        #expect(display.visibleUsage(ClaudeUsage(fiveHour: nil, sevenDay: usage.sevenDay)) == nil)
    }

    @MainActor
    @Test func olderReportsFromIdleSessionsNeverWinOverNewerOnes() {
        let clock = Date(timeIntervalSince1970: 1_000_000)
        let monitor = UsageMonitor(isEnabled: true, now: { clock })
        let current = clock.addingTimeInterval(3600)
        let weekly = UsageWindow(utilization: 40, resetsAt: clock.addingTimeInterval(86_400))
        monitor.receive(ClaudeUsage(fiveHour: UsageWindow(utilization: 60, resetsAt: current), sevenDay: weekly))

        monitor.receive(ClaudeUsage(fiveHour: UsageWindow(utilization: 10, resetsAt: current.addingTimeInterval(-5 * 3600)), sevenDay: weekly))
        #expect(monitor.usage?.fiveHour?.utilization == 60)

        monitor.receive(ClaudeUsage(fiveHour: UsageWindow(utilization: 55, resetsAt: current.addingTimeInterval(1)), sevenDay: weekly))
        #expect(monitor.usage?.fiveHour?.utilization == 60)

        monitor.receive(ClaudeUsage(fiveHour: nil, sevenDay: weekly))
        #expect(monitor.usage?.fiveHour?.utilization == 60)

        let next = UsageWindow(utilization: 3, resetsAt: current.addingTimeInterval(5 * 3600))
        monitor.receive(ClaudeUsage(fiveHour: next, sevenDay: weekly))
        #expect(monitor.usage?.fiveHour == next)
    }

    @MainActor
    @Test func theMonitorShowsResetWindowsAsUnusedUntilTheNextReport() {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let monitor = UsageMonitor(isEnabled: true, now: { clock })
        #expect(monitor.usage == nil)
        monitor.receive(ClaudeUsage(fiveHour: nil, sevenDay: nil))
        #expect(monitor.usage == nil)

        let fiveHour = UsageWindow(utilization: 30, resetsAt: clock.addingTimeInterval(60))
        let sevenDay = UsageWindow(utilization: 10, resetsAt: clock.addingTimeInterval(3600))
        monitor.receive(ClaudeUsage(fiveHour: fiveHour, sevenDay: sevenDay))
        #expect(monitor.usage == ClaudeUsage(fiveHour: fiveHour, sevenDay: sevenDay))

        clock = clock.addingTimeInterval(120)
        let unused = UsageWindow.unused
        #expect(monitor.usage == ClaudeUsage(fiveHour: unused, sevenDay: sevenDay))

        monitor.receive(ClaudeUsage(fiveHour: nil, sevenDay: sevenDay))
        #expect(monitor.usage == ClaudeUsage(fiveHour: unused, sevenDay: sevenDay))

        clock = clock.addingTimeInterval(3600)
        #expect(monitor.usage == ClaudeUsage(fiveHour: unused, sevenDay: unused))

        let fresh = UsageWindow(utilization: 5, resetsAt: clock.addingTimeInterval(5 * 3600))
        monitor.receive(ClaudeUsage(fiveHour: fresh, sevenDay: nil))
        #expect(monitor.usage == ClaudeUsage(fiveHour: fresh, sevenDay: unused))
    }
}
