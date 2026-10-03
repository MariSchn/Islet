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
    var volume: Int
    var isFavorite: Bool

    init(title: String, artist: String, album: String = "", artworkURL: URL? = nil, isPlaying: Bool, position: TimeInterval = 0, duration: TimeInterval = 0, isShuffling: Bool = false, repeatMode: RepeatMode = .off, volume: Int = 0, isFavorite: Bool = false) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.isPlaying = isPlaying
        self.position = position
        self.duration = duration
        self.isShuffling = isShuffling
        self.repeatMode = repeatMode
        self.volume = volume
        self.isFavorite = isFavorite
    }

    var progress: Double {
        duration > 0 ? min(max(position / duration, 0), 1) : 0
    }

    func position(at date: Date, fetchedAt: Date) -> TimeInterval {
        guard isPlaying else { return position }
        let advanced = position + date.timeIntervalSince(fetchedAt)
        return min(max(advanced, 0), max(duration, 0))
    }
}
