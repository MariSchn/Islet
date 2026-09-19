import Foundation
import IsletCore
import Testing
@testable import MediaPlugin

@MainActor
struct MediaControllerTests {
    @Test func publishesPillWhilePlayingAndClearsItWhenPaused() async {
        let source = StubSource()
        let controller = MediaController(source: source)
        var pills: [PillStatus?] = []
        controller.onPillChange = { pills.append($0) }

        await source.set(NowPlaying(title: "Song", artist: "Band", isPlaying: true))
        await controller.refresh()
        #expect(pills.last??.text == "Song · Band")
        #expect(pills.last??.priority == .ambient)

        await source.set(NowPlaying(title: "Song", artist: "Band", isPlaying: false))
        await controller.refresh()
        #expect(pills.last! == nil)
    }

    @Test func pillCanBeSwitchedOff() async {
        let source = StubSource()
        let controller = MediaController(source: source, showsPill: false)
        var pills: [PillStatus?] = []
        controller.onPillChange = { pills.append($0) }

        await source.set(NowPlaying(title: "Song", artist: "Band", isPlaying: true))
        await controller.refresh()
        #expect(pills.last! == nil)

        controller.showsPill = true
        #expect(pills.last??.text == "Song · Band")
    }

    @Test func commandsAreForwardedAndFollowedByRefresh() async {
        let source = StubSource()
        let controller = MediaController(source: source)
        await source.set(NowPlaying(title: "Song", artist: "Band", isPlaying: true))

        await controller.playPause()
        await controller.nextTrack()
        await controller.previousTrack()
        await controller.seek(to: 42)

        #expect(await source.commands == ["playPause", "next", "previous", "seek(42.0)"])
        #expect(controller.nowPlaying?.title == "Song")
    }

    @Test func errorsAreSurfacedAndClearNowPlaying() async {
        let source = StubSource()
        let controller = MediaController(source: source)
        await source.set(NowPlaying(title: "Song", artist: "Band", isPlaying: true))
        await controller.refresh()

        await source.fail(with: "denied")
        await controller.refresh()

        #expect(controller.nowPlaying == nil)
        #expect(controller.errorMessage == "denied")
    }

    @Test func stateChangeTriggersRefresh() async {
        let source = StubSource()
        let controller = MediaController(source: source, playingInterval: .seconds(60), pausedInterval: .seconds(60))
        controller.start()
        await source.set(NowPlaying(title: "First", artist: "Band", isPlaying: true))
        await source.set(NowPlaying(title: "Second", artist: "Band", isPlaying: true))
        source.notifyChange()

        await waitUntil { controller.nowPlaying?.title == "Second" }
        #expect(controller.nowPlaying?.title == "Second")
        controller.stop()
        #expect(controller.nowPlaying == nil)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<50 where !condition() {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}

private struct StubError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private actor StubState {
    var nowPlaying: NowPlaying?
    var error: String?
    var commands: [String] = []

    func set(_ value: NowPlaying?) { nowPlaying = value }
    func fail(with message: String) { error = message }
    func record(_ command: String) { commands.append(command) }
    func read() throws -> NowPlaying? {
        if let error { throw StubError(message: error) }
        return nowPlaying
    }
}

private struct StubSource: MediaSource {
    let displayName = "Stub"
    let bundleIdentifier = "com.apple.finder"
    private let state = StubState()
    let stateChanges: AsyncStream<Void>
    private let changes: AsyncStream<Void>.Continuation

    init() {
        (stateChanges, changes) = AsyncStream.makeStream()
    }

    var commands: [String] {
        get async { await state.commands }
    }

    func set(_ value: NowPlaying?) async { await state.set(value) }
    func fail(with message: String) async { await state.fail(with: message) }
    func notifyChange() { changes.yield() }

    func nowPlaying() async throws -> NowPlaying? { try await state.read() }
    func playPause() async throws { await state.record("playPause") }
    func nextTrack() async throws { await state.record("next") }
    func previousTrack() async throws { await state.record("previous") }
    func seek(to position: TimeInterval) async throws { await state.record("seek(\(position))") }
}
