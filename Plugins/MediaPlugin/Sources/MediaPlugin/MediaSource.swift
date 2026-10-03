import AppKit

enum RepeatMode: String, Sendable, Equatable, CaseIterable {
    case off
    case all
    case one
}

struct MediaPlaylist: Sendable, Equatable, Identifiable {
    let id: String
    let name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

struct MediaCapabilities: Sendable, Equatable {
    static let none = MediaCapabilities()

    var canShuffle: Bool
    var repeatModes: [RepeatMode]
    var canBrowsePlaylists: Bool
    var canSetVolume: Bool
    var canFavorite: Bool

    init(canShuffle: Bool = false, repeatModes: [RepeatMode] = [], canBrowsePlaylists: Bool = false, canSetVolume: Bool = false, canFavorite: Bool = false) {
        self.canShuffle = canShuffle
        self.repeatModes = repeatModes
        self.canBrowsePlaylists = canBrowsePlaylists
        self.canSetVolume = canSetVolume
        self.canFavorite = canFavorite
    }

    var canRepeat: Bool {
        repeatModes.count > 1
    }

    func repeatMode(after mode: RepeatMode) -> RepeatMode? {
        guard canRepeat else { return nil }
        guard let index = repeatModes.firstIndex(of: mode) else { return repeatModes.first }
        return repeatModes[(index + 1) % repeatModes.count]
    }
}

struct UnsupportedMediaCommand: LocalizedError {
    let sourceName: String

    var errorDescription: String? {
        "\(sourceName) does not support this."
    }
}

protocol MediaSource: Sendable {
    var displayName: String { get }
    var bundleIdentifier: String { get }
    var capabilities: MediaCapabilities { get }

    @MainActor var isRunning: Bool { get }
    @MainActor func launch()

    func stateChanges() -> AsyncStream<Void>
    func nowPlaying() async throws -> NowPlaying?
    func playPause() async throws
    func nextTrack() async throws
    func previousTrack() async throws
    func seek(to position: TimeInterval) async throws
    func setShuffling(_ shuffling: Bool) async throws
    func setRepeatMode(_ mode: RepeatMode) async throws
    func setVolume(_ volume: Int) async throws
    func setFavorite(_ favorite: Bool) async throws
    func playlists() async throws -> [MediaPlaylist]
    func play(_ playlist: MediaPlaylist) async throws
    func artwork(at url: URL) async throws -> Data
}

extension MediaSource {
    var capabilities: MediaCapabilities { .none }

    @MainActor
    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    @MainActor
    func launch() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func setShuffling(_ shuffling: Bool) async throws {
        throw UnsupportedMediaCommand(sourceName: displayName)
    }

    func setRepeatMode(_ mode: RepeatMode) async throws {
        throw UnsupportedMediaCommand(sourceName: displayName)
    }

    func setVolume(_ volume: Int) async throws {
        throw UnsupportedMediaCommand(sourceName: displayName)
    }

    func setFavorite(_ favorite: Bool) async throws {
        throw UnsupportedMediaCommand(sourceName: displayName)
    }

    func playlists() async throws -> [MediaPlaylist] {
        throw UnsupportedMediaCommand(sourceName: displayName)
    }

    func play(_ playlist: MediaPlaylist) async throws {
        throw UnsupportedMediaCommand(sourceName: displayName)
    }

    func artwork(at url: URL) async throws -> Data {
        try await URLSession.shared.data(from: url).0
    }
}
