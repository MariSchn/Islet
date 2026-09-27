import Foundation

public struct NowPlaying: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var artworkURL: URL?
    public var isPlaying: Bool
    public var position: TimeInterval
    public var duration: TimeInterval
    public var isShuffling: Bool
    public var repeatMode: RepeatMode

    public init(title: String, artist: String, album: String = "", artworkURL: URL? = nil, isPlaying: Bool, position: TimeInterval = 0, duration: TimeInterval = 0, isShuffling: Bool = false, repeatMode: RepeatMode = .off) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.isPlaying = isPlaying
        self.position = position
        self.duration = duration
        self.isShuffling = isShuffling
        self.repeatMode = repeatMode
    }

    public var progress: Double {
        duration > 0 ? min(max(position / duration, 0), 1) : 0
    }
}
