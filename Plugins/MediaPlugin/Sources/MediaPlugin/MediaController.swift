import Foundation
import IsletCore
import Observation
import SwiftUI

public typealias ArtworkLoader = @Sendable (URL) async throws -> Data

@MainActor
@Observable
public final class MediaController {
    public let source: any MediaSource
    public private(set) var nowPlaying: NowPlaying?
    public private(set) var artwork: CGImage?
    public private(set) var tint: Color.Resolved?
    public private(set) var isSourceRunning = false
    public private(set) var errorMessage: String?
    public var showsPill: Bool {
        didSet {
            guard showsPill != oldValue else { return }
            updatePill()
            onShowsPillChange(showsPill)
        }
    }
    @ObservationIgnored public var onPillChange: (PillStatus?) -> Void = { _ in }
    @ObservationIgnored public var onShowsPillChange: (Bool) -> Void = { _ in }

    @ObservationIgnored private let loadArtwork: ArtworkLoader
    @ObservationIgnored private let playingInterval: Duration
    @ObservationIgnored private let pausedInterval: Duration
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var changeTask: Task<Void, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var artworkURL: URL?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var publishedPill: PillStatus?

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
        updateArtwork(for: nil)
        updatePill()
    }

    public func refresh() async {
        isSourceRunning = source.isRunning
        guard isSourceRunning else {
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
