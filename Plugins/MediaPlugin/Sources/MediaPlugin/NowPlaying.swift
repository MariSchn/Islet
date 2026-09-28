import Foundation

struct NowPlaying: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String
    var artworkURL: URL?
    var isPlaying: Bool
    var position: TimeInterval
    var duration: TimeInterval
    var isShuffling: Bool
    var repeatMode: RepeatMode

    init(title: String, artist: String, album: String = "", artworkURL: URL? = nil, isPlaying: Bool, position: TimeInterval = 0, duration: TimeInterval = 0, isShuffling: Bool = false, repeatMode: RepeatMode = .off) {
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

    var progress: Double {
        duration > 0 ? min(max(position / duration, 0), 1) : 0
    }
}
