import Foundation
import IsletCore
import Observation
import SwiftUI

typealias ArtworkLoader = @Sendable (URL) async throws -> Data

@MainActor
@Observable
final class MediaController {
    private(set) var sources: [any MediaSource]
    private(set) var activeIndex = 0
    private(set) var nowPlaying: NowPlaying?
    private(set) var nowPlayingDate: Date?
    private(set) var artwork: CGImage?
    private(set) var tint: Color.Resolved?
    private(set) var isSourceRunning = false
    private(set) var errorMessage: String?
    private(set) var isBrowsingPlaylists = false
    private(set) var isLoadingPlaylists = false
    private(set) var playlists: [MediaPlaylist] = []
    private(set) var playlistError: String?
    var showsPill: Bool
    @ObservationIgnored var onCommandError: ((String) -> Void)?
    var isScreenVisible = false {
        didSet {
            guard isScreenVisible, !oldValue, pollTask != nil else { return }
            startPolling()
        }
    }

    @ObservationIgnored private let loadArtwork: ArtworkLoader?
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private let playingInterval: Duration
    @ObservationIgnored private let pausedInterval: Duration
    @ObservationIgnored private let hiddenInterval: Duration
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var changeTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var artworkURL: URL?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var browseGeneration = 0

    var source: (any MediaSource)? {
        sources.indices.contains(activeIndex) ? sources[activeIndex] : nil
    }

    convenience init(
        source: any MediaSource,
        showsPill: Bool = true,
        playingInterval: Duration = .seconds(1),
        pausedInterval: Duration = .seconds(3),
        hiddenInterval: Duration = .seconds(15),
        clock: @escaping @MainActor () -> Date = { Date() },
        loadArtwork: ArtworkLoader? = nil
    ) {
        self.init(sources: [source], showsPill: showsPill, playingInterval: playingInterval, pausedInterval: pausedInterval, hiddenInterval: hiddenInterval, clock: clock, loadArtwork: loadArtwork)
    }

    init(
        sources: [any MediaSource],
        showsPill: Bool = true,
        playingInterval: Duration = .seconds(1),
        pausedInterval: Duration = .seconds(3),
        hiddenInterval: Duration = .seconds(15),
        clock: @escaping @MainActor () -> Date = { Date() },
        loadArtwork: ArtworkLoader? = nil
    ) {
        self.sources = sources
        self.showsPill = showsPill
        self.playingInterval = playingInterval
        self.pausedInterval = pausedInterval
        self.hiddenInterval = hiddenInterval
        self.clock = clock
        self.loadArtwork = loadArtwork
    }

    var pillStatus: PillStatus? {
        guard showsPill, let nowPlaying, nowPlaying.isPlaying else { return nil }
        let text = [nowPlaying.title, nowPlaying.artist].filter { !$0.isEmpty }.joined(separator: " · ")
        return PillStatus(text: text, systemImage: "music.note", priority: .ambient, artwork: artwork, tint: tint)
    }

    private var pollInterval: Duration {
        guard isScreenVisible else { return hiddenInterval }
        return nowPlaying?.isPlaying == true ? playingInterval : pausedInterval
    }

    func start() {
        guard pollTask == nil else { return }
        startPolling()
        watchStateChanges()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await refresh()
                try? await Task.sleep(for: pollInterval)
            }
        }
    }

    private func watchStateChanges() {
        changeTasks.forEach { $0.cancel() }
        changeTasks = sources.map { source in
            Task { [weak self] in
                for await _ in source.stateChanges() {
                    guard let self else { return }
                    await refresh()
                }
            }
        }
    }

    func stop() {
        generation += 1
        pollTask?.cancel()
        changeTasks.forEach { $0.cancel() }
        pollTask = nil
        changeTasks.removeAll()
        nowPlaying = nil
        nowPlayingDate = nil
        errorMessage = nil
        hidePlaylists()
        updateArtwork(for: nil)
    }

    func replaceSources(_ sources: [any MediaSource]) {
        let wasStarted = pollTask != nil
        stop()
        self.sources = sources
        activeIndex = 0
        isSourceRunning = false
        playlists = []
        if wasStarted {
            start()
        }
    }

    func refresh() async {
        let sources = self.sources
        guard !sources.isEmpty else {
            isSourceRunning = false
            hidePlaylists()
            apply(nowPlaying: nil, error: nil)
            return
        }
        generation += 1
        let requested = generation
        var polls: [SourcePoll] = []
        for (index, source) in sources.enumerated() {
            guard source.isRunning else { continue }
            let outcome: Result<NowPlaying?, any Error>
            do {
                outcome = .success(try await source.nowPlaying())
            } catch {
                outcome = .failure(error)
            }
            let fetchedAt = clock()
            guard requested == generation else { return }
            polls.append(SourcePoll(index: index, outcome: outcome, fetchedAt: fetchedAt))
        }
        guard requested == generation else { return }
        let chosen = Self.preferredSourceIndex(among: polls, current: activeIndex)
        if sources.indices.contains(chosen), chosen != activeIndex {
            hidePlaylists()
            playlists = []
            activeIndex = chosen
        }
        if let poll = polls.first(where: { $0.index == activeIndex }) {
            apply(poll: poll)
        } else {
            isSourceRunning = false
            hidePlaylists()
            apply(nowPlaying: nil, error: nil)
        }
    }

    func playPause() async {
        await perform { try await $0.playPause() }
    }

    func nextTrack() async {
        await perform { try await $0.nextTrack() }
    }

    func previousTrack() async {
        await perform { try await $0.previousTrack() }
    }

    func seek(to position: TimeInterval) async {
        await perform { try await $0.seek(to: position) }
    }

    func setVolume(_ volume: Int) async {
        guard capabilities.canSetVolume else { return }
        let bounded = min(max(volume, 0), 100)
        await perform { try await $0.setVolume(bounded) }
    }

    func toggleFavorite() async {
        guard capabilities.canFavorite, let nowPlaying else { return }
        await perform { try await $0.setFavorite(!nowPlaying.isFavorite) }
    }

    var capabilities: MediaCapabilities {
        source?.capabilities ?? .none
    }

    func toggleShuffle() async {
        guard capabilities.canShuffle, let nowPlaying else { return }
        await perform { try await $0.setShuffling(!nowPlaying.isShuffling) }
    }

    func cycleRepeatMode() async {
        guard let nowPlaying, let next = capabilities.repeatMode(after: nowPlaying.repeatMode) else { return }
        await perform { try await $0.setRepeatMode(next) }
    }

    func togglePlaylists() async {
        if isBrowsingPlaylists {
            hidePlaylists()
        } else {
            await showPlaylists()
        }
    }

    func showPlaylists() async {
        guard let source = source, source.capabilities.canBrowsePlaylists, source.isRunning else { return }
        browseGeneration += 1
        let requested = browseGeneration
        isBrowsingPlaylists = true
        isLoadingPlaylists = playlists.isEmpty
        playlistError = nil
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
    }

    func hidePlaylists() {
        browseGeneration += 1
        isLoadingPlaylists = false
        playlistError = nil
        guard isBrowsingPlaylists else { return }
        isBrowsingPlaylists = false
    }

    func play(_ playlist: MediaPlaylist) async {
        guard let source else { return }
        guard source.isRunning else {
            isSourceRunning = false
            hidePlaylists()
            apply(nowPlaying: nil, error: nil)
            return
        }
        let requested = browseGeneration
        do {
            try await source.play(playlist)
            hidePlaylists()
        } catch let error as AppleScriptError where error.isApplicationNotRunning {
            hidePlaylists()
        } catch {
            if requested == browseGeneration, isBrowsingPlaylists {
                playlistError = error.localizedDescription
            }
        }
        await refresh()
    }

    func launch(_ source: any MediaSource) {
        source.launch()
    }

    private func perform(_ command: (any MediaSource) async throws -> Void) async {
        guard let source else { return }
        guard source.isRunning else {
            isSourceRunning = false
            apply(nowPlaying: nil, error: nil)
            return
        }
        do {
            try await command(source)
        } catch let error as AppleScriptError where error.isApplicationNotRunning {
            hidePlaylists()
        } catch {
            onCommandError?(error.localizedDescription)
        }
        await refresh()
    }

    private func apply(poll: SourcePoll) {
        switch poll.outcome {
        case .success(let nowPlaying):
            isSourceRunning = true
            apply(nowPlaying: nowPlaying, error: nil, fetchedAt: poll.fetchedAt)
        case .failure(let error as AppleScriptError) where error.isApplicationNotRunning:
            isSourceRunning = false
            hidePlaylists()
            apply(nowPlaying: nil, error: nil)
        case .failure(let error):
            isSourceRunning = true
            apply(nowPlaying: nil, error: error.localizedDescription)
        }
    }

    private func apply(nowPlaying: NowPlaying?, error: String?, fetchedAt: Date? = nil) {
        self.nowPlaying = nowPlaying
        nowPlayingDate = nowPlaying == nil ? nil : fetchedAt
        errorMessage = error
        updateArtwork(for: nowPlaying?.artworkURL)
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
        let source = self.source
        let load = loadArtwork ?? { [source] in
            guard let source else { throw CancellationError() }
            return try await source.artwork(at: $0)
        }
        artworkTask = Task { [weak self] in
            let loaded: Data?
            do {
                loaded = try await load(url)
            } catch is CancellationError {
                guard let self, artworkURL == url else { return }
                artworkURL = nil
                return
            } catch {
                loaded = nil
            }
            let artwork = await Task.detached { loaded.flatMap(Artwork.init(data:)) }.value
            guard let self, !Task.isCancelled, artworkURL == url else { return }
            self.artwork = artwork?.image
            tint = artwork?.tint
        }
    }

    private static func preferredSourceIndex(among polls: [SourcePoll], current: Int) -> Int {
        if let playing = polls.first(where: \.isPlaying) {
            return playing.index
        }
        if polls.contains(where: { $0.index == current && $0.hasTrack }) {
            return current
        }
        if let tracked = polls.first(where: \.hasTrack) {
            return tracked.index
        }
        return current
    }
}

private struct SourcePoll {
    let index: Int
    let outcome: Result<NowPlaying?, any Error>
    let fetchedAt: Date

    var track: NowPlaying? {
        if case .success(let nowPlaying) = outcome { return nowPlaying }
        return nil
    }

    var isPlaying: Bool { track?.isPlaying == true }
    var hasTrack: Bool { track != nil }
}
