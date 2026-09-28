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

    @Test func derivedPropertiesAreOnlyAppliedWhileThePluginIsActive() async throws {
        let registry = harness.makeRegistry()
        let stub = try await harness.registerStub(in: registry)
        let counter = Counter()
        stub.context.derive(\.pillStatus) { PillStatus(text: "\(counter.value)") }
        #expect(stub.context.pillStatus?.text == "0")

        await registry.setEnabled(false, for: StubPlugin.manifest.id)
        counter.value = 1
        try await Task.sleep(for: .milliseconds(50))
        #expect(stub.context.pillStatus == nil)

        await registry.setEnabled(true, for: StubPlugin.manifest.id)
        try await waitUntil { stub.context.pillStatus?.text == "1" }
    }

    @Test func observersRunOnlyOnRealChanges() async throws {
        let registry = harness.makeRegistry()
        let stub = try await harness.registerStub(in: registry)
        let counter = Counter()
        var seen: [Bool] = []
        stub.context.observe({ counter.value > 1 }) { seen.append($0) }
        #expect(seen.isEmpty)

        counter.value = 1
        try await Task.sleep(for: .milliseconds(50))
        #expect(seen.isEmpty)
        counter.value = 2
        try await waitUntil { seen == [true] }
        counter.value = 3
        try await Task.sleep(for: .milliseconds(50))
        #expect(seen == [true])
    }

    @Test func observersCanAlsoRunWithTheInitialValue() async throws {
        let registry = harness.makeRegistry()
        let stub = try await harness.registerStub(in: registry)
        let counter = Counter()
        var seen: [Int] = []
        stub.context.observe({ counter.value }, initial: true) { seen.append($0) }
        #expect(seen == [0])

        counter.value = 5
        try await waitUntil { seen == [0, 5] }
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
