import Foundation

public struct MusicSource: MediaSource {
    public let displayName = "Music"
    public let bundleIdentifier = "com.apple.Music"
    public let capabilities = MediaCapabilities(canShuffle: true, repeatModes: [.off, .all, .one], canBrowsePlaylists: true)

    private let runner = AppleScriptRunner()
    private let artworkDirectory: URL

    public init(artworkDirectory: URL = FileManager.default.temporaryDirectory.appending(path: "IsletMusicArtwork", directoryHint: .isDirectory)) {
        self.artworkDirectory = artworkDirectory
    }

    public func stateChanges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let center = DistributedNotificationCenter.default()
            nonisolated(unsafe) let token = center.addObserver(
                forName: Notification.Name("com.apple.Music.playerInfo"),
                object: nil,
                queue: nil
            ) { _ in continuation.yield() }
            continuation.onTermination = { _ in center.removeObserver(token) }
        }
    }

    public func nowPlaying() async throws -> NowPlaying? {
        let track = try await runner.run(Self.script("""
            if player state is stopped then return {}
            set t to current track
            set r to song repeat
            if r is one then
                set repeatMode to "one"
            else if r is all then
                set repeatMode to "all"
            else
                set repeatMode to "off"
            end if
            return {name of t, artist of t, album of t, persistent ID of t, player state is playing, player position, duration of t, shuffle enabled, repeatMode}
            """)) { Self.track(from: $0) }
        guard var track else { return nil }
        track.nowPlaying.artworkURL = try? await artworkURL(forTrack: track.persistentID)
        return track.nowPlaying
    }

    public func playPause() async throws {
        try await runner.run(Self.script("playpause"))
    }

    public func nextTrack() async throws {
        try await runner.run(Self.script("next track"))
    }

    public func previousTrack() async throws {
        try await runner.run(Self.script("previous track"))
    }

    public func seek(to position: TimeInterval) async throws {
        guard position.isFinite else { return }
        try await runner.run(Self.script("set player position to \(String(format: "%.3f", position))"), cached: false)
    }

    public func setShuffling(_ shuffling: Bool) async throws {
        try await runner.run(Self.script("set shuffle enabled to \(shuffling)"))
    }

    public func setRepeatMode(_ mode: RepeatMode) async throws {
        try await runner.run(Self.script("set song repeat to \(mode.rawValue)"))
    }

    public func playlists() async throws -> [MediaPlaylist] {
        try await runner.run(Self.script("""
            set ids to persistent ID of every user playlist whose special kind is none
            set names to name of every user playlist whose special kind is none
            return {ids, names}
            """, timeout: 10)) { Self.playlists(from: $0) }
    }

    public func play(_ playlist: MediaPlaylist) async throws {
        guard Self.isPersistentID(playlist.id) else { throw UnsupportedMediaCommand(sourceName: displayName) }
        try await runner.run(Self.script("play (first user playlist whose persistent ID is \"\(playlist.id)\")"), cached: false)
    }

    private func artworkURL(forTrack persistentID: String) async throws -> URL? {
        guard Self.isPersistentID(persistentID) else { return nil }
        let url = artworkDirectory.appending(path: persistentID)
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            return size > 0 ? url : nil
        }
        let artwork = try await runner.run(Self.script("""
            set t to current track
            if (count of artworks of t) is 0 then return {persistent ID of t}
            return {persistent ID of t, raw data of artwork 1 of t}
            """)) { Self.artwork(from: $0) }
        guard let artwork, artwork.persistentID == persistentID else { return nil }
        try FileManager.default.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
        try (artwork.data ?? Data()).write(to: url, options: .atomic)
        return artwork.data == nil ? nil : url
    }

    static func script(_ body: String, timeout: Int = 2) -> String {
        """
        if application "Music" is not running then error "Application isn't running." number -600
        with timeout of \(timeout) seconds
            tell application "Music"
                \(body)
            end tell
        end timeout
        """
    }

    static func isPersistentID(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy(\.isHexDigit)
    }

    static func track(from result: NSAppleEventDescriptor) -> (nowPlaying: NowPlaying, persistentID: String)? {
        guard result.numberOfItems == 9 else { return nil }
        let nowPlaying = NowPlaying(
            title: result.atIndex(1)?.stringValue ?? "",
            artist: result.atIndex(2)?.stringValue ?? "",
            album: result.atIndex(3)?.stringValue ?? "",
            isPlaying: result.atIndex(5)?.booleanValue ?? false,
            position: result.atIndex(6)?.doubleValue ?? 0,
            duration: result.atIndex(7)?.doubleValue ?? 0,
            isShuffling: result.atIndex(8)?.booleanValue ?? false,
            repeatMode: result.atIndex(9)?.stringValue.flatMap(RepeatMode.init(rawValue:)) ?? .off
        )
        return (nowPlaying, result.atIndex(4)?.stringValue ?? "")
    }

    static func playlists(from result: NSAppleEventDescriptor) -> [MediaPlaylist] {
        guard result.numberOfItems == 2, let ids = result.atIndex(1), let names = result.atIndex(2), ids.numberOfItems == names.numberOfItems, ids.numberOfItems > 0 else { return [] }
        return (1...ids.numberOfItems).compactMap { index in
            guard let id = ids.atIndex(index)?.stringValue, let name = names.atIndex(index)?.stringValue else { return nil }
            return MediaPlaylist(id: id, name: name)
        }
    }

    static func artwork(from result: NSAppleEventDescriptor) -> (persistentID: String, data: Data?)? {
        guard (1...2).contains(result.numberOfItems), let persistentID = result.atIndex(1)?.stringValue else { return nil }
        let data = result.numberOfItems == 2 ? result.atIndex(2)?.data : nil
        return (persistentID, data.flatMap { $0.isEmpty ? nil : $0 })
    }
}
