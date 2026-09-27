import Foundation
import IsletCore
import Observation
import SwiftUI

public typealias ArtworkLoader = @Sendable (URL) async throws -> Data

@MainActor
@Observable
public final class MediaController {
    public private(set) var source: any MediaSource
    public private(set) var nowPlaying: NowPlaying?
    public private(set) var artwork: CGImage?
    public private(set) var tint: Color.Resolved?
    public private(set) var isSourceRunning = false
    public private(set) var errorMessage: String?
    public private(set) var isBrowsingPlaylists = false
    public private(set) var isLoadingPlaylists = false
    public private(set) var playlists: [MediaPlaylist] = []
    public private(set) var playlistError: String?
    public var showsPill: Bool {
        didSet {
            guard showsPill != oldValue else { return }
            updatePill()
            onShowsPillChange(showsPill)
        }
    }
    @ObservationIgnored public var onPillChange: (PillStatus?) -> Void = { _ in }
    @ObservationIgnored public var onShowsPillChange: (Bool) -> Void = { _ in }
    @ObservationIgnored public var onLayoutChange: () -> Void = {}

    @ObservationIgnored private let loadArtwork: ArtworkLoader
    @ObservationIgnored private let playingInterval: Duration
    @ObservationIgnored private let pausedInterval: Duration
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var changeTask: Task<Void, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var artworkURL: URL?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var publishedPill: PillStatus?
    @ObservationIgnored private var browseGeneration = 0

    public init(
        source: any MediaSource,
        showsPill: Bool = true,
        playingInterval: Duration = .seconds(1),
        pausedInterval: Duration = .seconds(3),
        loadArtwork: @escaping ArtworkLoader = { try await URLSession.shared.data(from: $0).0 }
    ) {
        self.source = source
        self.showsPill = showsPill
        self.playingInterval = playingInterval
        self.pausedInterval = pausedInterval
        self.loadArtwork = loadArtwork
    }

    public func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await refresh()
                let interval = nowPlaying?.isPlaying == true ? playingInterval : pausedInterval
                try? await Task.sleep(for: interval)
            }
        }
        changeTask = Task { [weak self, source] in
            for await _ in source.stateChanges() {
                guard let self else { return }
                await refresh()
            }
        }
    }

    public func stop() {
        generation += 1
        pollTask?.cancel()
        changeTask?.cancel()
        pollTask = nil
        changeTask = nil
        nowPlaying = nil
        errorMessage = nil
        hidePlaylists()
        updateArtwork(for: nil)
        updatePill()
    }

    public func replaceSource(_ source: any MediaSource) {
        let wasStarted = pollTask != nil
        stop()
        self.source = source
        isSourceRunning = false
        playlists = []
        if wasStarted {
            start()
        }
    }

    public func refresh() async {
        isSourceRunning = source.isRunning
        guard isSourceRunning else {
            hidePlaylists()
            apply(nowPlaying: nil, error: nil)
            return
        }
        generation += 1
        let requested = generation
        let outcome: Result<NowPlaying?, any Error>
        do {
            outcome = .success(try await source.nowPlaying())
        } catch {
            outcome = .failure(error)
        }
        guard requested == generation else { return }
        switch outcome {
        case .success(let nowPlaying):
            apply(nowPlaying: nowPlaying, error: nil)
        case .failure(let error as AppleScriptError) where error.isApplicationNotRunning:
            isSourceRunning = false
            apply(nowPlaying: nil, error: nil)
        case .failure(let error):
            apply(nowPlaying: nil, error: error.localizedDescription)
        }
    }

    public func playPause() async {
        await perform { try await $0.playPause() }
    }

    public func nextTrack() async {
        await perform { try await $0.nextTrack() }
    }

    public func previousTrack() async {
        await perform { try await $0.previousTrack() }
    }

    public func seek(to position: TimeInterval) async {
        await perform { try await $0.seek(to: position) }
    }

    public var capabilities: MediaCapabilities {
        source.capabilities
    }

    public func toggleShuffle() async {
        guard capabilities.canShuffle, let nowPlaying else { return }
        await perform { try await $0.setShuffling(!nowPlaying.isShuffling) }
    }

    public func cycleRepeatMode() async {
        guard let nowPlaying, let next = capabilities.repeatMode(after: nowPlaying.repeatMode) else { return }
        await perform { try await $0.setRepeatMode(next) }
    }

    public func togglePlaylists() async {
        if isBrowsingPlaylists {
            hidePlaylists()
        } else {
            await showPlaylists()
        }
    }

    public func showPlaylists() async {
        guard capabilities.canBrowsePlaylists, source.isRunning else { return }
        browseGeneration += 1
        let requested = browseGeneration
        isBrowsingPlaylists = true
        isLoadingPlaylists = playlists.isEmpty
        playlistError = nil
        onLayoutChange()
        let outcome: Result<[MediaPlaylist], any Error>
        do {
            outcome = .success(try await source.playlists())
        } catch {
            outcome = .failure(error)
        }
        guard requested == browseGeneration else { return }
        isLoadingPlaylists = false
        switch outcome {
        case .success(let playlists):
            self.playlists = playlists
        case .failure(let error):
            playlists = []
            playlistError = error.localizedDescription
        }
        onLayoutChange()
    }

    public func hidePlaylists() {
        browseGeneration += 1
        isLoadingPlaylists = false
        playlistError = nil
        guard isBrowsingPlaylists else { return }
        isBrowsingPlaylists = false
        onLayoutChange()
    }

    public func play(_ playlist: MediaPlaylist) async {
        hidePlaylists()
        await perform { try await $0.play(playlist) }
    }

    public func launchSource() {
        source.launch()
    }

    private func perform(_ command: (any MediaSource) async throws -> Void) async {
        guard source.isRunning else {
            isSourceRunning = false
            apply(nowPlaying: nil, error: nil)
            return
        }
        do {
            try await command(source)
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
    }

    private func apply(nowPlaying: NowPlaying?, error: String?) {
        self.nowPlaying = nowPlaying
        errorMessage = error
        updateArtwork(for: nowPlaying?.artworkURL)
        updatePill()
    }

    private func updateArtwork(for url: URL?) {
        guard url != artworkURL else { return }
        artworkURL = url
        artworkTask?.cancel()
        guard let url else {
            artwork = nil
            tint = nil
            return
        }
        artworkTask = Task { [weak self, loadArtwork] in
            let loaded = try? await loadArtwork(url)
            let artwork = await Task.detached { loaded.flatMap(Artwork.init(data:)) }.value
            guard let self, !Task.isCancelled, artworkURL == url else { return }
            guard let artwork else {
                artworkURL = nil
                return
            }
            self.artwork = artwork.image
            tint = artwork.tint
            updatePill()
        }
    }

    private func updatePill() {
        let pill: PillStatus?
        if showsPill, let nowPlaying, nowPlaying.isPlaying {
            pill = PillStatus(text: "\(nowPlaying.title) · \(nowPlaying.artist)", systemImage: "music.note", priority: .ambient, artwork: artwork, tint: tint)
        } else {
            pill = nil
        }
        guard pill != publishedPill else { return }
        publishedPill = pill
        onPillChange(pill)
    }
}
