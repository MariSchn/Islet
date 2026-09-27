import AppKit

public enum RepeatMode: String, Sendable, Equatable, CaseIterable {
    case off
    case all
    case one
}

public struct MediaPlaylist: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct MediaCapabilities: Sendable, Equatable {
    public static let none = MediaCapabilities()

    public var canShuffle: Bool
    public var repeatModes: [RepeatMode]
    public var canBrowsePlaylists: Bool

    public init(canShuffle: Bool = false, repeatModes: [RepeatMode] = [], canBrowsePlaylists: Bool = false) {
        self.canShuffle = canShuffle
        self.repeatModes = repeatModes
        self.canBrowsePlaylists = canBrowsePlaylists
    }

    public var canRepeat: Bool {
        repeatModes.count > 1
    }

    public func repeatMode(after mode: RepeatMode) -> RepeatMode? {
        guard canRepeat else { return nil }
        guard let index = repeatModes.firstIndex(of: mode) else { return repeatModes.first }
        return repeatModes[(index + 1) % repeatModes.count]
    }
}

public struct UnsupportedMediaCommand: LocalizedError {
    public let sourceName: String

    public var errorDescription: String? {
        "\(sourceName) does not support this."
    }
}

public protocol MediaSource: Sendable {
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
    func playlists() async throws -> [MediaPlaylist]
    func play(_ playlist: MediaPlaylist) async throws
}

public extension MediaSource {
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

    func playlists() async throws -> [MediaPlaylist] {
        throw UnsupportedMediaCommand(sourceName: displayName)
    }

    func play(_ playlist: MediaPlaylist) async throws {
        throw UnsupportedMediaCommand(sourceName: displayName)
    }
}
