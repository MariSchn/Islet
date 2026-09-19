import Foundation

public struct SpotifySource: MediaSource {
    public let displayName = "Spotify"
    public let bundleIdentifier = "com.spotify.client"

    private let runner = AppleScriptRunner()

    public init() {}

    public var stateChanges: AsyncStream<Void> {
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
        try await runner.run("""
            tell application "Spotify"
                if player state is stopped then return {}
                set t to current track
                return {name of t, artist of t, album of t, artwork url of t, player state is playing, player position, duration of t}
            end tell
            """) { result in
            guard result.numberOfItems == 7 else { return nil }
            return NowPlaying(
                title: result.atIndex(1)?.stringValue ?? "",
                artist: result.atIndex(2)?.stringValue ?? "",
                album: result.atIndex(3)?.stringValue ?? "",
                artworkURL: result.atIndex(4)?.stringValue.flatMap(URL.init(string:)),
                isPlaying: result.atIndex(5)?.booleanValue ?? false,
                position: result.atIndex(6)?.doubleValue ?? 0,
                duration: Double(result.atIndex(7)?.int32Value ?? 0) / 1000
            )
        }
    }

    public func playPause() async throws {
        try await runner.run("tell application \"Spotify\" to playpause")
    }

    public func nextTrack() async throws {
        try await runner.run("tell application \"Spotify\" to next track")
    }

    public func previousTrack() async throws {
        try await runner.run("tell application \"Spotify\" to previous track")
    }

    public func seek(to position: TimeInterval) async throws {
        try await runner.run("tell application \"Spotify\" to set player position to \(position)")
    }
}
