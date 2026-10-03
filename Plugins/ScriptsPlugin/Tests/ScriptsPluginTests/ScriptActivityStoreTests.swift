import Foundation
import IsletCore
import Testing
@testable import ScriptsPlugin

@MainActor
struct ScriptActivityStoreTests {
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var date = Date(timeIntervalSince1970: 1_000_000)

        var now: Date {
            lock.lock()
            defer { lock.unlock() }
            return date
        }

        func advance(_ seconds: TimeInterval) {
            lock.lock()
            date.addTimeInterval(seconds)
            lock.unlock()
        }
    }

    private func request(_ id: String, text: String = "t", progress: Double? = nil, priority: PillStatus.Priority = .info, ttl: TimeInterval = 600) -> ScriptActivityRequest {
        ScriptActivityRequest(id: id, text: text, symbol: nil, progress: progress, priority: priority, ttl: ttl)
    }

    @Test func createsReplacesAndDeletes() {
        let clock = Clock()
        let store = ScriptActivityStore(now: { clock.now })
        store.upsert(request("a", text: "one"))
        store.upsert(request("b"))
        clock.advance(5)
        store.upsert(request("a", text: "two", progress: 0.3))
        #expect(store.activities.map(\.id) == ["b", "a"])
        #expect(store.newestFirst.first?.text == "two")
        #expect(store.newestFirst.first?.progress == 0.3)
        #expect(store.activities.last?.symbol == "bolt.fill")
        store.remove(id: "b")
        store.remove(id: "missing")
        #expect(store.activities.map(\.id) == ["a"])
    }

    @Test func removesExpiredActivities() {
        let clock = Clock()
        let store = ScriptActivityStore(now: { clock.now })
        store.upsert(request("short", ttl: 10))
        store.upsert(request("long", ttl: 100))
        clock.advance(10)
        store.removeExpired()
        #expect(store.activities.map(\.id) == ["long"])
        clock.advance(89)
        store.removeExpired()
        #expect(store.activities.count == 1)
        clock.advance(1)
        store.removeExpired()
        #expect(store.activities.isEmpty)
    }

    @Test func expiresOnItsOwnWhenTheTimeComes() async throws {
        let store = ScriptActivityStore()
        store.upsert(request("a", ttl: 0.05))
        let deadline = ContinuousClock.now + .seconds(3)
        while !store.activities.isEmpty {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func keepsAtMostFiftyActivities() {
        let store = ScriptActivityStore()
        for index in 0..<(ScriptActivityStore.limit + 5) {
            store.upsert(request("a\(index)"))
        }
        #expect(store.activities.count == ScriptActivityStore.limit)
        #expect(store.activities.first?.id == "a5")
        #expect(store.activities.last?.id == "a54")
    }

    @Test func pillPrefersPriorityThenRecency() {
        let store = ScriptActivityStore()
        #expect(store.pillStatus == nil)
        store.upsert(request("a", text: "first", priority: .info))
        store.upsert(request("b", text: "second", priority: .info))
        #expect(store.pillStatus?.text == "second")
        store.upsert(request("c", text: "loud", priority: .attention))
        store.upsert(request("d", text: "newest", priority: .info))
        #expect(store.pillStatus?.text == "loud")
        #expect(store.pillStatus?.priority == .attention)
        store.upsert(request("e", text: "louder", priority: .attention))
        #expect(store.pillStatus?.text == "louder")
        store.upsert(request("c", text: "loud again", priority: .attention))
        #expect(store.pillStatus?.text == "loud again")
    }

    @Test func pillRingShowsProgress() throws {
        let store = ScriptActivityStore()
        store.upsert(request("a", text: "Build", progress: 0.3))
        let ring = try #require(store.pillStatus?.ring)
        #expect(ring.segments.count == 2)
        #expect(ring.segments[0].value == 0.3)
        #expect(ring.segments[0].tint == ScriptActivityStore.progressTint)
        #expect(abs(ring.segments[1].value - 0.7) < 1e-9)
        #expect(ring.segments[1].tint == ScriptActivityStore.remainingTint)
        #expect(store.pillStatus?.systemImage == "bolt.fill")

        store.upsert(request("a", text: "Build", progress: 1))
        #expect(store.pillStatus?.ring?.segments.map(\.value) == [1])
        store.upsert(request("a", text: "Build", progress: 0))
        #expect(store.pillStatus?.ring?.segments.map(\.value) == [1])
        #expect(store.pillStatus?.ring?.segments.first?.tint == ScriptActivityStore.remainingTint)
        store.upsert(request("a", text: "Build"))
        #expect(store.pillStatus?.ring == nil)
    }
}
