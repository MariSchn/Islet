import CoreGraphics
import Foundation
import IsletCore
import IsletTestSupport
import Observation
import Testing

@MainActor
@Observable
final class Counter {
    var value = 0
}

@MainActor
struct PluginContextTests {
    let harness = Harness()

    func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
    }

    @Test func derivedPropertiesFollowTheirSourceAndRecoverWhenOverwritten() async throws {
        let registry = harness.makeRegistry()
        let stub = try await harness.registerStub(in: registry)
        let counter = Counter()
        stub.context.derive(\.contentSize) { CGSize(width: 100 + counter.value, height: 50) }
        #expect(stub.context.contentSize == CGSize(width: 100, height: 50))

        counter.value = 20
        try await waitUntil { stub.context.contentSize == CGSize(width: 120, height: 50) }

        stub.context.contentSize = nil
        try await waitUntil { stub.context.contentSize == CGSize(width: 120, height: 50) }
    }

    @Test func observersRunOnceAtFirstAndThenOnlyOnRealChanges() async throws {
        let registry = harness.makeRegistry()
        let stub = try await harness.registerStub(in: registry)
        let counter = Counter()
        var seen: [Bool] = []
        stub.context.observe({ counter.value > 1 }) { seen.append($0) }
        #expect(seen == [false])

        counter.value = 1
        counter.value = 2
        try await waitUntil { seen == [false, true] }
        counter.value = 3
        try await Task.sleep(for: .milliseconds(50))
        #expect(seen == [false, true])
    }

    @Test func onlyTheSelectedPluginIsVisibleWhileANotchIsExpanded() async throws {
        let registry = harness.makeRegistry()
        let first = try await harness.registerStub(in: registry)
        let second = try await harness.registerSecond(in: registry)
        let notch = NSObject()
        let otherNotch = NSObject()
        #expect(!first.context.isScreenVisible)

        registry.setNotchExpanded(true, by: notch)
        #expect(first.context.isScreenVisible)
        #expect(!second.context.isScreenVisible)

        registry.select(secondManifest.id)
        #expect(!first.context.isScreenVisible)
        #expect(second.context.isScreenVisible)

        registry.setNotchExpanded(true, by: otherNotch)
        registry.setNotchExpanded(false, by: notch)
        #expect(second.context.isScreenVisible)

        await registry.setEnabled(false, for: secondManifest.id)
        #expect(!second.context.isScreenVisible)
        #expect(first.context.isScreenVisible)

        registry.setNotchExpanded(false, by: otherNotch)
        #expect(!first.context.isScreenVisible)
    }
}
