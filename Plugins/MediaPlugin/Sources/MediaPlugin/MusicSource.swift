import Foundation

public struct MusicSource: MediaSource {
    public let displayName = "Music"
    public let bundleIdentifier = "com.apple.Music"
    public let capabilities = MediaCapabilities(canShuffle: true, repeatModes: [.off, .all, .one], canBrowsePlaylists: true)

    private let runner = AppleScriptRunner()
    private let browsingRunner = AppleScriptRunner()
    private let artworkFailures = ArtworkFailures()

    public init() {}

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
        try await runner.run(Self.nowPlayingScript) { Self.track(from: $0) }
    }

    public func playPause() async throws {
        try await runner.run(Self.playPauseScript)
    }

    public func nextTrack() async throws {
        try await runner.run(Self.nextTrackScript)
    }

    public func previousTrack() async throws {
        try await runner.run(Self.previousTrackScript)
    }

    public func seek(to position: TimeInterval) async throws {
        guard position.isFinite else { return }
        try await runner.run(Self.seekScript(to: position), cached: false)
    }

    public func setShuffling(_ shuffling: Bool) async throws {
        try await runner.run(Self.shuffleScript(shuffling))
    }

    public func setRepeatMode(_ mode: RepeatMode) async throws {
        try await runner.run(Self.repeatScript(mode))
    }

    public func playlists() async throws -> [MediaPlaylist] {
        try await browsingRunner.run(Self.playlistsScript) { Self.playlists(from: $0) }
    }

    public func play(_ playlist: MediaPlaylist) async throws {
        guard let script = Self.playScript(playlistID: playlist.id) else { throw UnsupportedMediaCommand(sourceName: displayName) }
        try await runner.run(script, cached: false)
    }

    public func artwork(at url: URL) async throws -> Data {
        guard let persistentID = Self.persistentID(fromArtworkURL: url) else { throw MissingArtwork() }
        guard await !artworkFailures.contains(persistentID) else { throw MissingArtwork() }
        let artwork: (persistentID: String, data: Data?)?
        do {
            artwork = try await runner.run(Self.artworkScript) { Self.artwork(from: $0) }
        } catch let error as AppleScriptError where !error.isApplicationNotRunning {
            await artworkFailures.insert(persistentID)
            throw error
        }
        guard let artwork, artwork.persistentID == persistentID else { throw CancellationError() }
        guard let data = artwork.data else {
            await artworkFailures.insert(persistentID)
            throw MissingArtwork()
        }
        return data
    }

    static let nowPlayingScript = script("""
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
        """)
    static let playPauseScript = script("playpause")
    static let nextTrackScript = script("next track")
    static let previousTrackScript = script("previous track")
    static let artworkScript = script("""
        set t to current track
        if (count of artworks of t) is 0 then return {persistent ID of t}
        return {persistent ID of t, raw data of artwork 1 of t}
        """)
    static let playlistsScript = script("""
        set found to {}
        repeat with p in (every user playlist whose special kind is none)
            set end of found to {persistent ID of p, name of p}
        end repeat
        repeat with p in every subscription playlist
            set end of found to {persistent ID of p, name of p}
        end repeat
        return found
        """, timeout: 10)
    static let artworkScheme = "islet-music-artwork"

    static func seekScript(to position: TimeInterval) -> String {
        script("set player position to \(String(format: "%.3f", position))")
    }

    static func shuffleScript(_ shuffling: Bool) -> String {
        script("set shuffle enabled to \(shuffling)")
    }

    static func repeatScript(_ mode: RepeatMode) -> String {
        script("set song repeat to \(mode.rawValue)")
    }

    static func playScript(playlistID: String) -> String? {
        guard isPersistentID(playlistID) else { return nil }
        return script("play (first playlist whose persistent ID is \"\(playlistID)\")")
    }

    static func artworkURL(forTrack persistentID: String) -> URL? {
        guard isPersistentID(persistentID) else { return nil }
        return URL(string: "\(artworkScheme):\(persistentID)")
    }

    static func persistentID(fromArtworkURL url: URL) -> String? {
        let prefix = "\(artworkScheme):"
        let value = url.absoluteString
        guard value.hasPrefix(prefix) else { return nil }
        let persistentID = String(value.dropFirst(prefix.count))
        return isPersistentID(persistentID) ? persistentID : nil
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

    static func track(from result: NSAppleEventDescriptor) -> NowPlaying? {
        guard result.numberOfItems == 9 else { return nil }
        return NowPlaying(
            title: result.atIndex(1)?.stringValue ?? "",
            artist: result.atIndex(2)?.stringValue ?? "",
            album: result.atIndex(3)?.stringValue ?? "",
            artworkURL: result.atIndex(4)?.stringValue.flatMap(artworkURL(forTrack:)),
            isPlaying: result.atIndex(5)?.booleanValue ?? false,
            position: result.atIndex(6)?.doubleValue ?? 0,
            duration: result.atIndex(7)?.doubleValue ?? 0,
            isShuffling: result.atIndex(8)?.booleanValue ?? false,
            repeatMode: result.atIndex(9)?.stringValue.flatMap(RepeatMode.init(rawValue:)) ?? .off
        )
    }

    static func playlists(from result: NSAppleEventDescriptor) -> [MediaPlaylist] {
        guard result.numberOfItems > 0 else { return [] }
        return (1...result.numberOfItems).compactMap { index in
            guard let pair = result.atIndex(index), pair.numberOfItems == 2,
                  let id = pair.atIndex(1)?.stringValue, let name = pair.atIndex(2)?.stringValue
            else { return nil }
            return MediaPlaylist(id: id, name: name)
        }
    }

    static func artwork(from result: NSAppleEventDescriptor) -> (persistentID: String, data: Data?)? {
        guard (1...2).contains(result.numberOfItems), let persistentID = result.atIndex(1)?.stringValue else { return nil }
        let data = result.numberOfItems == 2 ? result.atIndex(2)?.data : nil
        return (persistentID, data.flatMap { $0.isEmpty ? nil : $0 })
    }
}

struct MissingArtwork: Error {}

private actor ArtworkFailures {
    private var persistentIDs: Set<String> = []

    func contains(_ persistentID: String) -> Bool {
        persistentIDs.contains(persistentID)
    }

    func insert(_ persistentID: String) {
        persistentIDs.insert(persistentID)
    }
}
