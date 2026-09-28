import Foundation

public struct SpotifySource: MediaSource {
    public let displayName = "Spotify"
    public let bundleIdentifier = "com.spotify.client"
    public let capabilities = MediaCapabilities(canShuffle: true, repeatModes: [.off, .all])

    private let runner = AppleScriptRunner()

    public init() {}

    public func stateChanges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let center = DistributedNotificationCenter.default()
            nonisolated(unsafe) let token = center.addObserver(
                forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
                object: nil,
                queue: nil
            ) { _ in continuation.yield() }
            continuation.onTermination = { _ in center.removeObserver(token) }
        }
    }

    public func nowPlaying() async throws -> NowPlaying? {
        try await runner.run(Self.nowPlayingScript) { Self.nowPlaying(from: $0) }
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

    static let nowPlayingScript = script("""
        if player state is stopped then return {}
        set t to current track
        return {name of t, artist of t, album of t, artwork url of t, player state is playing, player position, duration of t, shuffling, repeating}
        """)
    static let playPauseScript = script("playpause")
    static let nextTrackScript = script("next track")
    static let previousTrackScript = script("previous track")

    static func seekScript(to position: TimeInterval) -> String {
        script("set player position to \(String(format: "%.3f", position))")
    }

    static func shuffleScript(_ shuffling: Bool) -> String {
        script("set shuffling to \(shuffling)")
    }

    static func repeatScript(_ mode: RepeatMode) -> String {
        script("set repeating to \(mode != .off)")
    }

    static func script(_ body: String) -> String {
        """
        if application "Spotify" is not running then error "Application isn't running." number -600
        with timeout of 2 seconds
            tell application "Spotify"
                \(body)
            end tell
        end timeout
        """
    }

    static func nowPlaying(from result: NSAppleEventDescriptor) -> NowPlaying? {
        guard result.numberOfItems == 9 else { return nil }
        return NowPlaying(
            title: result.atIndex(1)?.stringValue ?? "",
            artist: result.atIndex(2)?.stringValue ?? "",
            album: result.atIndex(3)?.stringValue ?? "",
            artworkURL: result.atIndex(4)?.stringValue.flatMap(URL.init(string:)),
            isPlaying: result.atIndex(5)?.booleanValue ?? false,
            position: result.atIndex(6)?.doubleValue ?? 0,
            duration: Double(result.atIndex(7)?.int32Value ?? 0) / 1000,
            isShuffling: result.atIndex(8)?.booleanValue ?? false,
            repeatMode: result.atIndex(9)?.booleanValue == true ? .all : .off
        )
    }
}
