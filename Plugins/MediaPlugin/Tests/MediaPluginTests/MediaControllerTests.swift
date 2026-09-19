import AppKit
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
        #expect(pills.last == .some(nil))
    }

    @Test func unchangedStatusIsNotRepublished() async {
        let source = StubSource()
        let controller = MediaController(source: source)
        var publishCount = 0
        controller.onPillChange = { _ in publishCount += 1 }

        await source.set(NowPlaying(title: "Song", artist: "Band", isPlaying: true, position: 1))
        await controller.refresh()
        await source.set(NowPlaying(title: "Song", artist: "Band", isPlaying: true, position: 2))
        await controller.refresh()

        #expect(publishCount == 1)
    }

    @Test func pillCanBeSwitchedOffAndPersists() async {
        let source = StubSource()
        let controller = MediaController(source: source, showsPill: false)
        var pills: [PillStatus?] = []
        var persisted: [Bool] = []
        controller.onPillChange = { pills.append($0) }
        controller.onShowsPillChange = { persisted.append($0) }

        await source.set(NowPlaying(title: "Song", artist: "Band", isPlaying: true))
        await controller.refresh()
        #expect(pills.isEmpty)

        controller.showsPill = true
        #expect(pills.last??.text == "Song · Band")
        #expect(persisted == [true])
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

    @Test func notRunningSourceIsNotQueried() async {
        let source = StubSource(isRunning: false)
        let controller = MediaController(source: source)
        await source.set(NowPlaying(title: "Song", artist: "Band", isPlaying: true))

        await controller.refresh()
        await controller.playPause()

        #expect(!controller.isSourceRunning)
        #expect(controller.nowPlaying == nil)
        #expect(await source.reads == 0)
        #expect(await source.commands.isEmpty)
    }

    @Test func stateChangeTriggersRefresh() async {
        let source = StubSource()
        let controller = MediaController(source: source, playingInterval: .seconds(60), pausedInterval: .seconds(60))
        await source.set(NowPlaying(title: "First", artist: "Band", isPlaying: true))
        controller.start()
        await waitUntil { controller.nowPlaying?.title == "First" }

        await source.set(NowPlaying(title: "Second", artist: "Band", isPlaying: true))
        source.notifyChange()

        await waitUntil { controller.nowPlaying?.title == "Second" }
        #expect(controller.nowPlaying?.title == "Second")
        controller.stop()
        #expect(controller.nowPlaying == nil)
    }

    @Test func staleRefreshResultIsDiscardedAfterStop() async {
        let source = StubSource()
        let controller = MediaController(source: source)
        await source.set(NowPlaying(title: "Song", artist: "Band", isPlaying: true))
        await source.setReadDelay(.milliseconds(100))

        async let refresh: Void = controller.refresh()
        try? await Task.sleep(for: .milliseconds(20))
        controller.stop()
        await refresh

        #expect(controller.nowPlaying == nil)
    }

    @Test func artworkIsLoadedAndPublishedWithTint() async {
        let source = StubSource()
        let url = URL(string: "https://example.com/cover.png")!
        let controller = MediaController(source: source) { requested in
            #expect(requested == url)
            return solidImageData(red: 0.9, green: 0.1, blue: 0.1)
        }
        var pills: [PillStatus?] = []
        controller.onPillChange = { pills.append($0) }

        await source.set(NowPlaying(title: "Song", artist: "Band", artworkURL: url, isPlaying: true))
        await controller.refresh()
        await waitUntil { controller.artwork != nil }

        #expect(controller.artwork?.width == Artwork.thumbnailSide)
        #expect(pills.last??.artwork != nil)
        let tint = try? #require(pills.last??.tint)
        #expect((tint?.red ?? 0) > (tint?.green ?? 0))
        #expect((tint?.red ?? 0) > 0.7)
    }

    @Test func artworkFromSupersededTrackIsIgnored() async {
        let source = StubSource()
        let slow = URL(string: "https://example.com/slow.png")!
        let fast = URL(string: "https://example.com/fast.png")!
        let controller = MediaController(source: source) { requested in
            if requested == slow {
                try await Task.sleep(for: .milliseconds(150))
                return solidImageData(red: 0, green: 0, blue: 1)
            }
            return solidImageData(red: 0, green: 1, blue: 0)
        }

        await source.set(NowPlaying(title: "Slow", artist: "Band", artworkURL: slow, isPlaying: true))
        await controller.refresh()
        await source.set(NowPlaying(title: "Fast", artist: "Band", artworkURL: fast, isPlaying: true))
        await controller.refresh()
        await waitUntil { controller.tint != nil }
        try? await Task.sleep(for: .milliseconds(200))

        let tint = controller.tint
        #expect((tint?.green ?? 0) > (tint?.blue ?? 0))
    }

    @Test func failedArtworkLoadKeepsPreviousArtworkAndRetriesLater() async {
        let source = StubSource()
        let first = URL(string: "https://example.com/first.png")!
        let second = URL(string: "https://example.com/second.png")!
        let attempts = Attempts()
        let controller = MediaController(source: source) { requested in
            await attempts.record(requested)
            if requested == second, await attempts.count(of: second) == 1 {
                throw StubError(message: "offline")
            }
            return solidImageData(red: 1, green: 1, blue: 0)
        }

        await source.set(NowPlaying(title: "First", artist: "Band", artworkURL: first, isPlaying: true))
        await controller.refresh()
        await waitUntil { controller.artwork != nil }
        let firstArtwork = controller.artwork

        await source.set(NowPlaying(title: "Second", artist: "Band", artworkURL: second, isPlaying: true))
        await controller.refresh()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(controller.artwork === firstArtwork)

        await controller.refresh()
        await waitUntil { await attempts.count(of: second) == 2 }
        #expect(await attempts.count(of: second) == 2)
    }

    private func waitUntil(_ condition: () async -> Bool) async {
        for _ in 0..<100 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}

struct SpotifyParsingTests {
    @Test func parsesSevenItemList() {
        let list = NSAppleEventDescriptor.list()
        for (index, item) in [
            NSAppleEventDescriptor(string: "Song"),
            NSAppleEventDescriptor(string: "Band"),
            NSAppleEventDescriptor(string: "Album"),
            NSAppleEventDescriptor(string: "https://i.scdn.co/image/abc"),
            NSAppleEventDescriptor(boolean: true),
            NSAppleEventDescriptor(double: 12.5),
            NSAppleEventDescriptor(int32: 185_000),
        ].enumerated() {
            list.insert(item, at: index + 1)
        }

        let nowPlaying = SpotifySource.nowPlaying(from: list)

        #expect(nowPlaying == NowPlaying(title: "Song", artist: "Band", album: "Album", artworkURL: URL(string: "https://i.scdn.co/image/abc"), isPlaying: true, position: 12.5, duration: 185))
    }

    @Test func emptyListMeansNothingPlaying() {
        #expect(SpotifySource.nowPlaying(from: NSAppleEventDescriptor.list()) == nil)
    }

    @Test func missingArtworkURLIsTolerated() {
        let list = NSAppleEventDescriptor.list()
        for (index, item) in [
            NSAppleEventDescriptor(string: "Local"),
            NSAppleEventDescriptor(string: "Me"),
            NSAppleEventDescriptor(string: ""),
            NSAppleEventDescriptor.null(),
            NSAppleEventDescriptor(boolean: false),
            NSAppleEventDescriptor(double: 0),
            NSAppleEventDescriptor(int32: 1000),
        ].enumerated() {
            list.insert(item, at: index + 1)
        }

        let nowPlaying = SpotifySource.nowPlaying(from: list)

        #expect(nowPlaying?.artworkURL == nil)
        #expect(nowPlaying?.duration == 1)
    }

    @Test func automationDenialGetsActionableMessage() {
        let error = AppleScriptError([NSAppleScript.errorNumber: -1743, NSAppleScript.errorMessage: "Not authorized"])
        #expect(error.localizedDescription.contains("Automation"))
        #expect(!error.isApplicationNotRunning)
        #expect(AppleScriptError([NSAppleScript.errorNumber: -600]).isApplicationNotRunning)
    }
}

struct ArtworkTests {
    @Test func darkCoverGetsLegibleTint() throws {
        let artwork = try #require(Artwork(data: solidImageData(red: 0.2, green: 0.05, blue: 0.05)))
        let tint = artwork.tint
        #expect(tint.red > 0.7)
        #expect(tint.red > tint.green)
        #expect(artwork.image.width == Artwork.thumbnailSide)
    }

    @Test func garbageDataYieldsNoArtwork() {
        #expect(Artwork(data: Data("not an image".utf8)) == nil)
    }
}

private func solidImageData(red: CGFloat, green: CGFloat, blue: CGFloat) -> Data {
    let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
        NSColor(red: red, green: green, blue: blue, alpha: 1).setFill()
        rect.fill()
        return true
    }
    let tiff = image.tiffRepresentation!
    return NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
}

private struct StubError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private actor Attempts {
    private var urls: [URL] = []
    func record(_ url: URL) { urls.append(url) }
    func count(of url: URL) -> Int { urls.filter { $0 == url }.count }
}

private actor StubState {
    var nowPlaying: NowPlaying?
    var error: String?
    var commands: [String] = []
    var reads = 0
    var readDelay: Duration?

    func set(_ value: NowPlaying?) { nowPlaying = value }
    func fail(with message: String) { error = message }
    func record(_ command: String) { commands.append(command) }
    func setReadDelay(_ delay: Duration) { readDelay = delay }
    func read() async throws -> NowPlaying? {
        reads += 1
        if let readDelay { try? await Task.sleep(for: readDelay) }
        if let error { throw StubError(message: error) }
        return nowPlaying
    }
}

private struct StubSource: MediaSource {
    let displayName = "Stub"
    let bundleIdentifier = "com.example.stub"
    let isRunning: Bool
    private let state = StubState()
    private let stream: AsyncStream<Void>
    private let changes: AsyncStream<Void>.Continuation

    init(isRunning: Bool = true) {
        self.isRunning = isRunning
        (stream, changes) = AsyncStream.makeStream()
    }

    var commands: [String] {
        get async { await state.commands }
    }

    var reads: Int {
        get async { await state.reads }
    }

    func launch() {}
    func stateChanges() -> AsyncStream<Void> { stream }
    func set(_ value: NowPlaying?) async { await state.set(value) }
    func fail(with message: String) async { await state.fail(with: message) }
    func setReadDelay(_ delay: Duration) async { await state.setReadDelay(delay) }
    func notifyChange() { changes.yield() }

    func nowPlaying() async throws -> NowPlaying? { try await state.read() }
    func playPause() async throws { await state.record("playPause") }
    func nextTrack() async throws { await state.record("next") }
    func previousTrack() async throws { await state.record("previous") }
    func seek(to position: TimeInterval) async throws { await state.record("seek(\(position))") }
}
