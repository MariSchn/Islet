import Foundation
import IsletCore
import Testing
@testable import AgentsPlugin

@MainActor
struct AgentsPluginSizingTests {
    @Test func contentGrowsWithSessionsUpToAScrollingMaximum() {
        func sessions(_ count: Int) -> [AgentSession] {
            (0..<count).map { AgentSession(id: "\($0)", agent: .claudeCode, host: nil, cwd: nil, task: nil, activity: nil, state: .working, startedAt: .now, turnStartedAt: .now, updatedAt: .now) }
        }
        #expect(AgentsPlugin.contentSize(for: [], expanded: [], showsUsage: false, historyLength: 8) == CGSize(width: 520, height: 130))
        #expect(AgentsPlugin.contentSize(for: sessions(1), expanded: [], showsUsage: false, historyLength: 8) == CGSize(width: 520, height: 92))
        #expect(AgentsPlugin.contentSize(for: sessions(2), expanded: [], showsUsage: false, historyLength: 8) == CGSize(width: 520, height: 166))
        #expect(AgentsPlugin.contentSize(for: sessions(4), expanded: [], showsUsage: false, historyLength: 8) == AgentsPlugin.contentSize(for: sessions(9), expanded: [], showsUsage: false, historyLength: 8))
        let usage = AgentsPlugin.usageBarHeight + AgentsPlugin.rowSpacing
        #expect(AgentsPlugin.contentSize(for: [], expanded: [], showsUsage: true, historyLength: 8).height == 130 + usage)
        #expect(AgentsPlugin.contentSize(for: sessions(1), expanded: [], showsUsage: true, historyLength: 8).height == 92 + usage)
        #expect(AgentsPlugin.contentSize(for: sessions(9), expanded: [], showsUsage: true, historyLength: 8).height == AgentsPlugin.maxContentHeight + usage)
    }

    @Test func expandedRowsShowAtMostTheConfiguredNumberOfActions() {
        var session = AgentSession(id: "a", agent: .claudeCode, host: nil, cwd: nil, task: nil, activity: nil, state: .working, startedAt: .now, turnStartedAt: .now, updatedAt: .now)
        session.activities = (0..<10).map { index in ActivityEntry(event: HookEvent(kind: .preToolUse, sessionID: "a", toolName: "Grep", toolInput: .object(["pattern": .string("\(index)")])), at: .now, isComplete: true) }
        let three = AgentsPlugin.contentSize(for: [session], expanded: ["a"], showsUsage: false, historyLength: 3).height
        let five = AgentsPlugin.contentSize(for: [session], expanded: ["a"], showsUsage: false, historyLength: 5).height
        #expect(five == three + 2 * AgentsPlugin.activityEntryHeight)
        #expect(AgentsPlugin.visibleActivities(of: session, historyLength: 3).map(\.title) == ["Search 7", "Search 8", "Search 9"])
        #expect(AgentsPlugin.visibleActivities(of: session, historyLength: 20).count == 10)
        #expect(AgentsPlugin.contentSize(for: [session], expanded: [], showsUsage: false, historyLength: 3) == AgentsPlugin.contentSize(for: [session], expanded: [], showsUsage: false, historyLength: 5))
    }

    @Test func historyLengthStaysWithinItsRange() {
        var display = DisplaySettings()
        #expect(display.historyLength == 8)
        display.historyLength = 0
        #expect(display.historyLength == DisplaySettings.historyLengthRange.lowerBound)
        display.historyLength = 500
        #expect(display.historyLength == ActivityEntry.limit)
    }

    @Test func pendingRequestsMakeRowsTaller() {
        var session = AgentSession(id: "a", agent: .claudeCode, host: nil, cwd: nil, task: nil, activity: nil, state: .working, startedAt: .now, turnStartedAt: .now, updatedAt: .now)
        let plain = AgentsPlugin.contentSize(for: [session], expanded: [], showsUsage: false, historyLength: 8).height
        session.pendingRequests = [PendingRequest(toolName: "Bash", toolInput: .object(["command": .string("ls")]))!]
        let permission = AgentsPlugin.contentSize(for: [session], expanded: [], showsUsage: false, historyLength: 8).height
        #expect(permission > plain)
        session.pendingRequests = [PendingRequest(toolName: "AskUserQuestion", toolInput: .object([
            "questions": .array([
                .object(["question": .string("Which?"), "options": .array([.object(["label": .string("A")]), .object(["label": .string("B")]), .object(["label": .string("C")])])]),
                .object(["question": .string("Multi?"), "multiSelect": .bool(true), "options": .array([.object(["label": .string("X")])])]),
            ]),
        ]))!]
        let question = AgentsPlugin.contentSize(for: [session], expanded: [], showsUsage: false, historyLength: 8).height
        #expect(question > permission)
        #expect(question <= AgentsPlugin.maxContentHeight)
    }

    @Test func expandedRowsGrowWithActivityAndPlan() {
        var session = AgentSession(id: "a", agent: .claudeCode, host: nil, cwd: nil, task: nil, activity: nil, state: .working, startedAt: .now, turnStartedAt: .now, updatedAt: .now)
        let collapsed = AgentsPlugin.contentSize(for: [session], expanded: [], showsUsage: false, historyLength: 8).height
        let empty = AgentsPlugin.contentSize(for: [session], expanded: ["a"], showsUsage: false, historyLength: 8).height
        #expect(empty > collapsed)
        session.activities = (0..<3).map { _ in ActivityEntry(event: HookEvent(kind: .preToolUse, sessionID: "a", toolName: "Read"), at: .now, isComplete: true) }
        let withActivity = AgentsPlugin.contentSize(for: [session], expanded: ["a"], showsUsage: false, historyLength: 8).height
        #expect(withActivity == empty + 2 * AgentsPlugin.activityEntryHeight)
        session.plan = "# Plan"
        #expect(AgentsPlugin.contentSize(for: [session], expanded: ["a"], showsUsage: false, historyLength: 8).height > withActivity)
    }
}
