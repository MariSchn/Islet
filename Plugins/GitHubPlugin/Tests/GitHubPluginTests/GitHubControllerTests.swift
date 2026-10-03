import Foundation
import Testing
@testable import GitHubPlugin

@MainActor
struct GitHubControllerTests {
    final class Clock {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func makeController(_ client: StubClient, clock: Clock = Clock(), network: @escaping NetworkUpdates = networkNeverChanges) -> GitHubController {
        GitHubController(client: client, networkUpdates: network, now: { clock.now })
    }

    @Test func loadsPullRequestsOnStart() async throws {
        let client = StubClient([.success(snapshot(mine: 2, review: 1))])
        let controller = makeController(client)
        #expect(controller.phase == .loading)
        controller.start()
        defer { controller.stop() }
        try await waitUntil { controller.phase.snapshot != nil }
        #expect(controller.phase.snapshot?.mine.count == 2)
        #expect(controller.failures == 0)
    }

    @Test func mapsErrorsToTheirPhases() async {
        let cases: [(GitHubError, GitHubPhase)] = [
            (.ghMissing, .ghMissing),
            (.notLoggedIn, .notLoggedIn),
            (.failed("Bad credentials"), .failed("Bad credentials")),
            (.timedOut, .failed(GitHubError.timedOut.localizedDescription)),
        ]
        for (error, phase) in cases {
            let controller = makeController(StubClient([.failure(error)]))
            await controller.refresh()
            #expect(controller.phase == phase)
        }
    }

    @Test func backsOffAfterFailuresAndResetsAfterASuccess() async {
        let client = StubClient([.failure(.failed("down")), .failure(.failed("down")), .failure(.failed("down")), .success(snapshot(mine: 1, review: 0))])
        let controller = makeController(client)
        await controller.refresh()
        #expect(controller.pollInterval == .seconds(60))
        await controller.refresh()
        #expect(controller.pollInterval == .seconds(120))
        await controller.refresh()
        #expect(controller.failures == 3)
        #expect(controller.pollInterval == .seconds(240))
        await controller.refresh()
        #expect(controller.failures == 0)
        #expect(controller.pollInterval == .seconds(120))
        controller.isScreenVisible = true
        #expect(controller.pollInterval == .seconds(60))
    }

    @Test func refreshesWhenTheScreenAppearsAfterThirtySeconds() async throws {
        let clock = Clock()
        let client = StubClient([.success(snapshot(mine: 1, review: 0))])
        let controller = makeController(client, clock: clock)
        controller.start()
        defer { controller.stop() }
        try await waitUntil { controller.phase.snapshot != nil }
        #expect(client.fetchCount == 1)

        clock.now += 10
        controller.isScreenVisible = true
        try await Task.sleep(for: .milliseconds(100))
        #expect(client.fetchCount == 1)

        controller.isScreenVisible = false
        clock.now += 25
        controller.isScreenVisible = true
        try await waitUntil { client.fetchCount == 2 }
    }

    @Test func skipsFetchingWhileOffline() async throws {
        let (updates, network) = AsyncStream<Bool>.makeStream()
        let clock = Clock()
        let client = StubClient([.success(snapshot(mine: 1, review: 0)), .success(snapshot(mine: 2, review: 0))])
        let controller = makeController(client, clock: clock, network: { updates })
        controller.start()
        defer { controller.stop() }
        try await waitUntil { controller.phase.snapshot != nil }

        network.yield(false)
        try await waitUntil { !controller.isOnline }
        await controller.refresh()
        #expect(client.fetchCount == 1)

        clock.now += 60
        network.yield(true)
        try await waitUntil { controller.phase.snapshot?.mine.count == 2 }
        #expect(client.fetchCount == 2)
    }

    @Test func retriesRightAwayWhenTheNetworkReturnsAfterAFailure() async throws {
        let (updates, network) = AsyncStream<Bool>.makeStream()
        let client = StubClient([.failure(.failed("The network connection was lost.")), .success(snapshot(mine: 1, review: 0))])
        let controller = makeController(client, network: { updates })
        controller.start()
        defer { controller.stop() }
        try await waitUntil { controller.failures == 1 }

        network.yield(false)
        try await waitUntil { !controller.isOnline }
        network.yield(true)
        try await waitUntil { controller.phase.snapshot != nil }
        #expect(client.fetchCount == 2)
    }

    @Test func stopResetsTheState() async throws {
        let controller = makeController(StubClient([.failure(.notLoggedIn)]))
        controller.start()
        try await waitUntil { controller.phase == .notLoggedIn }
        controller.stop()
        #expect(controller.phase == .loading)
        #expect(controller.failures == 0)
        #expect(controller.lastFetch == nil)
    }
}
