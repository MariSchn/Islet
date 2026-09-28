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

    @Test func failedArtworkLoadKeepsPreviousArtworkAndRetriesOnlyWhenTheTrackReturns() async {
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
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await attempts.count(of: second) == 1)

        await source.set(NowPlaying(title: "First", artist: "Band", artworkURL: first, isPlaying: true))
        await controller.refresh()
        await source.set(NowPlaying(title: "Second", artist: "Band", artworkURL: second, isPlaying: true))
        await controller.refresh()
        await waitUntil { await attempts.count(of: second) == 2 }
        #expect(await attempts.count(of: second) == 2)
    }

    @Test func artworkIsLoadedFromTheSourceByDefault() async {
        let source = StubSource()
        let controller = MediaController(source: source)
        await source.setArtwork(solidImageData(red: 0.9, green: 0.1, blue: 0.1))

        await source.set(NowPlaying(title: "Song", artist: "Band", artworkURL: URL(string: "stub:cover"), isPlaying: true))
        await controller.refresh()
        await waitUntil { controller.artwork != nil }

        #expect(controller.artwork != nil)
    }

    @Test func shuffleAndRepeatAreToggledWhenSupported() async {
        let source = StubSource(capabilities: MediaCapabilities(canShuffle: true, repeatModes: [.off, .all, .one]))
        let controller = MediaController(source: source)
        await source.set(NowPlaying(title: "Song", artist: "Band", isPlaying: true))
        await controller.refresh()

        await controller.toggleShuffle()
        await controller.cycleRepeatMode()
        await controller.cycleRepeatMode()
        await controller.cycleRepeatMode()

        #expect(await source.commands == ["shuffle(true)", "repeat(all)", "repeat(one)", "repeat(off)"])
        #expect(controller.nowPlaying?.isShuffling == true)
        #expect(controller.nowPlaying?.repeatMode == .off)
    }

    @Test func unsupportedControlsAreNotSent() async {
        let source = StubSource()
        let controller = MediaController(source: source)
        await source.set(NowPlaying(title: "Song", artist: "Band", isPlaying: true))
        await controller.refresh()

        await controller.toggleShuffle()
        await controller.cycleRepeatMode()
        await controller.showPlaylists()

        #expect(await source.commands.isEmpty)
        #expect(!controller.isBrowsingPlaylists)
    }

    @Test func browsingLoadsPlaylistsAndPlayingOneClosesTheBrowser() async {
        let source = StubSource(capabilities: MediaCapabilities(canBrowsePlaylists: true))
        let controller = MediaController(source: source)
        var layoutChanges = 0
        controller.onLayoutChange = { layoutChanges += 1 }
        let focus = MediaPlaylist(id: "AA11", name: "Focus")
        await source.setPlaylists([focus])

        await controller.togglePlaylists()
        #expect(controller.isBrowsingPlaylists)
        #expect(!controller.isLoadingPlaylists)
        #expect(controller.playlists == [focus])
        #expect(layoutChanges == 2)

        await controller.play(focus)
        #expect(!controller.isBrowsingPlaylists)
        #expect(await source.commands == ["play(Focus)"])
        #expect(layoutChanges == 3)
    }

    @Test func playlistErrorsAreShownInTheBrowser() async {
        let source = StubSource(capabilities: MediaCapabilities(canBrowsePlaylists: true))
        let controller = MediaController(source: source)
        await source.failPlaylists(with: "denied")

        await controller.showPlaylists()

        #expect(controller.isBrowsingPlaylists)
        #expect(controller.playlistError == "denied")
        #expect(controller.playlists.isEmpty)

        await controller.togglePlaylists()
        #expect(!controller.isBrowsingPlaylists)
        #expect(controller.playlistError == nil)
    }

    @Test func failedPlaylistPlaybackKeepsTheBrowserOpenWithTheError() async {
        let source = StubSource(capabilities: MediaCapabilities(canBrowsePlaylists: true))
        let controller = MediaController(source: source)
        let focus = MediaPlaylist(id: "AA11", name: "Focus")
        await source.setPlaylists([focus])
        await controller.showPlaylists()
        await source.failPlay(with: "gone")

        await controller.play(focus)

        #expect(controller.isBrowsingPlaylists)
        #expect(controller.playlistError == "gone")
        #expect(controller.playlists == [focus])
    }

    @Test func stalePlaylistResultIsDroppedAfterHiding() async {
        let source = StubSource(capabilities: MediaCapabilities(canBrowsePlaylists: true))
        let controller = MediaController(source: source)
        await source.setPlaylists([MediaPlaylist(id: "AA11", name: "Focus")])
        await source.setPlaylistDelay(.milliseconds(100))

        async let showing: Void = controller.showPlaylists()
        try? await Task.sleep(for: .milliseconds(20))
        controller.hidePlaylists()
        await showing

        #expect(!controller.isBrowsingPlaylists)
        #expect(!controller.isLoadingPlaylists)
        #expect(controller.playlists.isEmpty)
    }

    @Test func stalePlaylistResultIsDroppedAfterReplacingTheSource() async {
        let first = StubSource(capabilities: MediaCapabilities(canBrowsePlaylists: true))
        let controller = MediaController(source: first)
        await first.setPlaylists([MediaPlaylist(id: "AA11", name: "Focus")])
        await first.setPlaylistDelay(.milliseconds(100))

        async let showing: Void = controller.showPlaylists()
        try? await Task.sleep(for: .milliseconds(20))
        controller.replaceSource(StubSource(capabilities: MediaCapabilities(canBrowsePlaylists: true)))
        await showing

        #expect(!controller.isBrowsingPlaylists)
        #expect(controller.playlists.isEmpty)
    }

    @Test func browserClosesWhenTheSourceStopsRunning() async {
        let source = StubSource(capabilities: MediaCapabilities(canBrowsePlaylists: true))
        let controller = MediaController(source: source)
        await source.setPlaylists([MediaPlaylist(id: "AA11", name: "Focus")])
        await controller.showPlaylists()
        #expect(controller.isBrowsingPlaylists)

        source.setRunning(false)
        await controller.refresh()

        #expect(!controller.isBrowsingPlaylists)
        #expect(!controller.isSourceRunning)
    }

    @Test func browserClosesWhenACommandReportsTheAppQuit() async {
        let source = StubSource(capabilities: MediaCapabilities(canBrowsePlaylists: true))
        let controller = MediaController(source: source)
        await source.setPlaylists([MediaPlaylist(id: "AA11", name: "Focus")])
        await controller.showPlaylists()
        await source.failCommands(with: AppleScriptError([NSAppleScript.errorNumber: -600]))

        await controller.playPause()

        #expect(!controller.isBrowsingPlaylists)
        #expect(controller.errorMessage == nil)
    }

    @Test func replacingTheSourceClosesTheBrowserAndReadsTheNewSource() async {
        let first = StubSource(capabilities: MediaCapabilities(canBrowsePlaylists: true))
        let second = StubSource()
        let controller = MediaController(source: first)
        await first.setPlaylists([MediaPlaylist(id: "AA11", name: "Focus")])
        await controller.showPlaylists()
        await second.set(NowPlaying(title: "Other", artist: "Band", isPlaying: true))

        controller.replaceSource(second)
        await controller.refresh()

        #expect(!controller.isBrowsingPlaylists)
        #expect(controller.playlists.isEmpty)
        #expect(controller.nowPlaying?.title == "Other")
        #expect(!controller.capabilities.canBrowsePlaylists)
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
            NSAppleEventDescriptor(boolean: true),
            NSAppleEventDescriptor(boolean: true),
        ].enumerated() {
            list.insert(item, at: index + 1)
        }

        let nowPlaying = SpotifySource.nowPlaying(from: list)

        #expect(nowPlaying == NowPlaying(title: "Song", artist: "Band", album: "Album", artworkURL: URL(string: "https://i.scdn.co/image/abc"), isPlaying: true, position: 12.5, duration: 185, isShuffling: true, repeatMode: .all))
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
            NSAppleEventDescriptor(boolean: false),
            NSAppleEventDescriptor(boolean: false),
        ].enumerated() {
            list.insert(item, at: index + 1)
        }

        let nowPlaying = SpotifySource.nowPlaying(from: list)

        #expect(nowPlaying?.artworkURL == nil)
        #expect(nowPlaying?.duration == 1)
        #expect(nowPlaying?.isShuffling == false)
        #expect(nowPlaying?.repeatMode == .off)
    }

    @Test func spotifyCanShuffleAndRepeatButNotBrowse() {
        let capabilities = SpotifySource().capabilities
        #expect(capabilities.canShuffle)
        #expect(capabilities.canRepeat)
        #expect(capabilities.repeatMode(after: .all) == .off)
        #expect(!capabilities.canBrowsePlaylists)
    }

    @Test func automationDenialGetsActionableMessage() {
        let error = AppleScriptError([NSAppleScript.errorNumber: -1743, NSAppleScript.errorMessage: "Not authorized"])
        #expect(error.localizedDescription.contains("Automation"))
        #expect(!error.isApplicationNotRunning)
        #expect(AppleScriptError([NSAppleScript.errorNumber: -600]).isApplicationNotRunning)
    }
}

struct MusicParsingTests {
    @Test func parsesTrackWithShuffleAndRepeatOne() throws {
        let list = descriptorList([
            NSAppleEventDescriptor(string: "Song"),
            NSAppleEventDescriptor(string: "Band"),
            NSAppleEventDescriptor(string: "Album"),
            NSAppleEventDescriptor(string: "0A1B2C3D4E5F6789"),
            NSAppleEventDescriptor(boolean: true),
            NSAppleEventDescriptor(double: 30),
            NSAppleEventDescriptor(double: 241.5),
            NSAppleEventDescriptor(boolean: true),
            NSAppleEventDescriptor(string: "one"),
        ])

        let track = try #require(MusicSource.track(from: list))
        let artworkURL = try #require(track.artworkURL)

        #expect(MusicSource.persistentID(fromArtworkURL: artworkURL) == "0A1B2C3D4E5F6789")
        #expect(track == NowPlaying(title: "Song", artist: "Band", album: "Album", artworkURL: artworkURL, isPlaying: true, position: 30, duration: 241.5, isShuffling: true, repeatMode: .one))
    }

    @Test func artworkURLsOnlyCarryHexPersistentIDs() throws {
        #expect(MusicSource.artworkURL(forTrack: "AA\" & quit") == nil)
        #expect(MusicSource.persistentID(fromArtworkURL: try #require(URL(string: "https://example.com/AA11"))) == nil)
        #expect(MusicSource.persistentID(fromArtworkURL: try #require(MusicSource.artworkURL(forTrack: "AA11"))) == "AA11")
    }

    @Test func emptyListMeansNothingPlaying() {
        #expect(MusicSource.track(from: NSAppleEventDescriptor.list()) == nil)
    }

    @Test func parsesPlaylistsFromPairs() {
        let result = descriptorList([
            descriptorList([NSAppleEventDescriptor(string: "AA11"), NSAppleEventDescriptor(string: "Road Trip")]),
            descriptorList([NSAppleEventDescriptor(string: "BB22"), NSAppleEventDescriptor(string: "Focus")]),
        ])

        #expect(MusicSource.playlists(from: result) == [MediaPlaylist(id: "AA11", name: "Road Trip"), MediaPlaylist(id: "BB22", name: "Focus")])
    }

    @Test func malformedOrEmptyPlaylistPairsAreSkipped() {
        let malformed = descriptorList([
            descriptorList([NSAppleEventDescriptor(string: "AA11")]),
            descriptorList([NSAppleEventDescriptor(string: "BB22"), NSAppleEventDescriptor(string: "Focus")]),
        ])
        #expect(MusicSource.playlists(from: malformed) == [MediaPlaylist(id: "BB22", name: "Focus")])
        #expect(MusicSource.playlists(from: descriptorList([])).isEmpty)
    }

    @Test func parsesArtworkWithAndWithoutData() throws {
        let bytes = Data([0xFF, 0xD8, 0xFF])
        let withData = descriptorList([
            NSAppleEventDescriptor(string: "AA11"),
            try #require(NSAppleEventDescriptor(descriptorType: 0x4A50_4547, data: bytes)),
        ])
        let parsed = try #require(MusicSource.artwork(from: withData))
        #expect(parsed.persistentID == "AA11")
        #expect(parsed.data == bytes)

        let withoutData = try #require(MusicSource.artwork(from: descriptorList([NSAppleEventDescriptor(string: "AA11")])))
        #expect(withoutData.data == nil)
    }

    @Test func onlyHexPersistentIDsAreAccepted() {
        #expect(MusicSource.isPersistentID("0A1B2C3D4E5F6789"))
        #expect(MusicSource.playScript(playlistID: "AA\" & quit") == nil)
        #expect(!MusicSource.isPersistentID(""))
        #expect(!MusicSource.isPersistentID("AA\" & quit"))
    }

    @Test func musicSupportsAllRepeatModesAndBrowsing() {
        let capabilities = MusicSource().capabilities
        #expect(capabilities.canShuffle)
        #expect(capabilities.canBrowsePlaylists)
        #expect(capabilities.repeatMode(after: .off) == .all)
        #expect(capabilities.repeatMode(after: .all) == .one)
        #expect(capabilities.repeatMode(after: .one) == .off)
    }
}

@MainActor
struct AppleScriptCompilationTests {
    @Test func spotifyScriptsCompile() {
        let scripts = [
            SpotifySource.nowPlayingScript,
            SpotifySource.playPauseScript,
            SpotifySource.nextTrackScript,
            SpotifySource.previousTrackScript,
            SpotifySource.seekScript(to: 12.5),
            SpotifySource.shuffleScript(true),
            SpotifySource.shuffleScript(false),
        ] + RepeatMode.allCases.map(SpotifySource.repeatScript)
        for script in scripts {
            #expect(compileError(script) == nil, "\(script)")
        }
    }

    @Test func musicScriptsCompile() throws {
        let scripts = [
            MusicSource.nowPlayingScript,
            MusicSource.playPauseScript,
            MusicSource.nextTrackScript,
            MusicSource.previousTrackScript,
            MusicSource.artworkScript,
            MusicSource.playlistsScript,
            MusicSource.seekScript(to: 12.5),
            MusicSource.shuffleScript(true),
            MusicSource.shuffleScript(false),
            try #require(MusicSource.playScript(playlistID: "0A1B2C3D4E5F6789")),
        ] + RepeatMode.allCases.map(MusicSource.repeatScript)
        for script in scripts {
            #expect(compileError(script) == nil, "\(script)")
        }
    }

    @Test func unknownTermsFailToCompile() {
        #expect(compileError(MusicSource.script("get every imaginary playlist")) != nil)
    }

    private func compileError(_ source: String) -> NSDictionary? {
        guard let script = NSAppleScript(source: source) else { return [:] }
        var error: NSDictionary?
        return script.compileAndReturnError(&error) ? nil : (error ?? [:])
    }
}

@MainActor
struct MediaPlayerSettingTests {
    @Test func unknownOrMissingSettingFallsBackToSpotify() {
        #expect(MediaPlayer(setting: nil) == .spotify)
        #expect(MediaPlayer(setting: "vlc") == .spotify)
        #expect(MediaPlayer(setting: "music") == .music)
    }

    @Test func selectedPlayerIsPersistedAndRestored() async throws {
        let suite = "MediaPlayerSettingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set([MediaPlugin.manifest.id], forKey: "islet.disabledPlugins")
        let storage = FileManager.default.temporaryDirectory.appending(path: suite, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: storage) }

        let first = try await makePlugin(defaults: defaults, storage: storage)
        #expect(first.player == .spotify)
        first.select(.music)
        #expect(defaults.string(forKey: "plugin.\(MediaPlugin.manifest.id).\(MediaPlugin.playerKey)") == "music")

        let restored = try await makePlugin(defaults: defaults, storage: storage)
        #expect(restored.player == .music)
    }

    private func makePlugin(defaults: UserDefaults, storage: URL) async throws -> MediaPlugin {
        let registry = PluginRegistry(storageRoot: storage, userDefaults: defaults)
        let entry = try await registry.register(manifest: MediaPlugin.manifest) { MediaPlugin(context: $0) }
        return try #require(entry.plugin as? MediaPlugin)
    }
}

struct MediaCapabilitiesTests {
    @Test func noCapabilitiesMeansNoRepeatCycle() {
        #expect(MediaCapabilities.none.repeatMode(after: .off) == nil)
        #expect(MediaCapabilities(repeatModes: [.off]).repeatMode(after: .off) == nil)
    }

    @Test func unknownModeStartsTheCycleOver() {
        #expect(MediaCapabilities(repeatModes: [.off, .all]).repeatMode(after: .one) == .off)
    }
}

@MainActor
struct MediaLayoutTests {
    @Test func browserGrowsWithPlaylistsUpToALimit() {
        let collapsed = MediaPlugin.contentSize(isBrowsing: false, playlistCount: 20)
        let empty = MediaPlugin.contentSize(isBrowsing: true, playlistCount: 0)
        let one = MediaPlugin.contentSize(isBrowsing: true, playlistCount: 1)
        let three = MediaPlugin.contentSize(isBrowsing: true, playlistCount: 3)
        let many = MediaPlugin.contentSize(isBrowsing: true, playlistCount: 50)

        #expect(collapsed == CGSize(width: 420, height: 160))
        #expect(empty == one)
        #expect(one.height == collapsed.height + MediaPlugin.browserSpacing + MediaPlugin.browserHeaderHeight + MediaPlugin.playlistRowHeight)
        #expect(three.height - one.height == 2 * MediaPlugin.playlistRowHeight)
        #expect(many == MediaPlugin.contentSize(isBrowsing: true, playlistCount: MediaPlugin.maxVisiblePlaylistRows))
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

private func descriptorList(_ items: [NSAppleEventDescriptor]) -> NSAppleEventDescriptor {
    let list = NSAppleEventDescriptor.list()
    for (index, item) in items.enumerated() {
        list.insert(item, at: index + 1)
    }
    return list
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
    var playlists: [MediaPlaylist] = []
    var playlistError: String?
    var playlistDelay: Duration?
    var playError: String?
    var commandError: (any Error)?
    var artwork = Data()

    func set(_ value: NowPlaying?) { nowPlaying = value }
    func fail(with message: String) { error = message }
    func record(_ command: String) { commands.append(command) }
    func setReadDelay(_ delay: Duration) { readDelay = delay }
    func update(_ change: @Sendable (inout NowPlaying) -> Void) {
        guard var value = nowPlaying else { return }
        change(&value)
        nowPlaying = value
    }
    func setPlaylists(_ value: [MediaPlaylist]) { playlists = value }
    func failPlaylists(with message: String) { playlistError = message }
    func setPlaylistDelay(_ delay: Duration) { playlistDelay = delay }
    func failPlay(with message: String) { playError = message }
    func failCommands(with error: any Error) { commandError = error }
    func setArtwork(_ data: Data) { artwork = data }
    func perform(_ command: String) throws {
        if let commandError { throw commandError }
        commands.append(command)
    }
    func playPlaylist(_ playlist: MediaPlaylist) throws {
        if let playError { throw StubError(message: playError) }
        commands.append("play(\(playlist.name))")
    }
    func readPlaylists() async throws -> [MediaPlaylist] {
        if let playlistDelay { try? await Task.sleep(for: playlistDelay) }
        if let playlistError { throw StubError(message: playlistError) }
        return playlists
    }
    func read() async throws -> NowPlaying? {
        reads += 1
        if let readDelay { try? await Task.sleep(for: readDelay) }
        if let error { throw StubError(message: error) }
        return nowPlaying
    }
}

@MainActor
private final class StubRunning {
    var value: Bool

    init(_ value: Bool) {
        self.value = value
    }
}

private struct StubSource: MediaSource {
    let displayName = "Stub"
    let bundleIdentifier = "com.example.stub"
    let capabilities: MediaCapabilities
    private let running: StubRunning
    private let state = StubState()
    private let stream: AsyncStream<Void>
    private let changes: AsyncStream<Void>.Continuation

    @MainActor
    init(isRunning: Bool = true, capabilities: MediaCapabilities = .none) {
        running = StubRunning(isRunning)
        self.capabilities = capabilities
        (stream, changes) = AsyncStream.makeStream()
    }

    var commands: [String] {
        get async { await state.commands }
    }

    var reads: Int {
        get async { await state.reads }
    }

    @MainActor var isRunning: Bool { running.value }
    @MainActor func setRunning(_ value: Bool) { running.value = value }

    func launch() {}
    func stateChanges() -> AsyncStream<Void> { stream }
    func set(_ value: NowPlaying?) async { await state.set(value) }
    func fail(with message: String) async { await state.fail(with: message) }
    func setReadDelay(_ delay: Duration) async { await state.setReadDelay(delay) }
    func notifyChange() { changes.yield() }
    func setPlaylists(_ value: [MediaPlaylist]) async { await state.setPlaylists(value) }
    func failPlaylists(with message: String) async { await state.failPlaylists(with: message) }
    func setPlaylistDelay(_ delay: Duration) async { await state.setPlaylistDelay(delay) }
    func failPlay(with message: String) async { await state.failPlay(with: message) }
    func failCommands(with error: any Error) async { await state.failCommands(with: error) }
    func setArtwork(_ data: Data) async { await state.setArtwork(data) }

    func nowPlaying() async throws -> NowPlaying? { try await state.read() }
    func playPause() async throws { try await state.perform("playPause") }
    func nextTrack() async throws { await state.record("next") }
    func previousTrack() async throws { await state.record("previous") }
    func seek(to position: TimeInterval) async throws { await state.record("seek(\(position))") }
    func setShuffling(_ shuffling: Bool) async throws {
        await state.record("shuffle(\(shuffling))")
        await state.update { $0.isShuffling = shuffling }
    }
    func setRepeatMode(_ mode: RepeatMode) async throws {
        await state.record("repeat(\(mode.rawValue))")
        await state.update { $0.repeatMode = mode }
    }
    func playlists() async throws -> [MediaPlaylist] { try await state.readPlaylists() }
    func play(_ playlist: MediaPlaylist) async throws { try await state.playPlaylist(playlist) }
    func artwork(at url: URL) async throws -> Data { await state.artwork }
}
