import Foundation
import IsletCore
import Testing
@testable import AgentsPlugin

struct UsageTests {
    @Test func decodesUsageWindowsAndSkipsMissingOnes() throws {
        let usage = try ClaudeUsage.decode(Data(#"{"five_hour":{"utilization":11.5,"resets_at":"2026-09-20T18:00:00.5+00:00"},"seven_day":{"utilization":2,"resets_at":"2026-09-27T09:00:00Z"},"seven_day_opus":null}"#.utf8))
        #expect(usage.fiveHour?.utilization == 11.5)
        #expect(usage.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_789_927_200.5))
        #expect(usage.sevenDay?.utilization == 2)
        #expect(usage.sevenDay?.resetsAt == Date(timeIntervalSince1970: 1_790_499_600))
        #expect(try ClaudeUsage.decode(Data("{}".utf8)).isEmpty)
        #expect(throws: UsageError.unexpectedResponse) { try ClaudeUsage.decode(Data("[]".utf8)) }
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

    @Test func readsTheAccessTokenFromTheLoginFile() {
        #expect(ClaudeCredentials.accessToken(from: Data(#"{"claudeAiOauth":{"accessToken":"token-from-test","expiresAt":1}}"#.utf8)) == "token-from-test")
        #expect(ClaudeCredentials.accessToken(from: Data("{}".utf8)) == nil)
    }

    @MainActor
    @Test func monitorSendsTheBearerTokenAndReportsFailures() async throws {
        let requests = Requests()
        let token = Box(value: "token-from-test")
        let status = StatusBox()
        let monitor = UsageMonitor(isEnabled: true, accessToken: { token.value }, load: { request in
            await requests.record(request)
            return (Data(#"{"five_hour":{"utilization":40,"resets_at":null}}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: status.value, httpVersion: nil, headerFields: nil)!)
        })
        monitor.refresh(force: true)
        try await waitUntil { monitor.usage != nil }
        #expect(monitor.usage == ClaudeUsage(fiveHour: UsageWindow(utilization: 40, resetsAt: nil), sevenDay: nil))
        let request = await requests.all.first
        #expect(request?.url == UsageMonitor.endpoint)
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer token-from-test")
        #expect(request?.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")

        monitor.refresh()
        try await Task.sleep(for: .milliseconds(50))
        #expect(await requests.all.count == 1)

        status.value = 503
        monitor.refresh(force: true)
        try await waitUntil { monitor.error != nil }
        #expect(monitor.error == UsageError.status(503).errorDescription)
        #expect(monitor.usage != nil)

        status.value = 200
        monitor.refresh(force: true)
        try await waitUntil { monitor.error == nil }

        token.value = nil
        monitor.refresh(force: true)
        try await waitUntil { monitor.usage == nil }
        #expect(monitor.error == UsageError.notLoggedIn.errorDescription)

        monitor.isEnabled = false
        #expect(monitor.error == nil)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out")
    }

    private actor Requests {
        var all: [URLRequest] = []
        func record(_ request: URLRequest) { all.append(request) }
    }

    private final class Box: @unchecked Sendable {
        var value: String?
        init(value: String?) { self.value = value }
    }

    private final class StatusBox: @unchecked Sendable {
        var value = 200
    }
}
