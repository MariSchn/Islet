import Foundation
import IsletCore
import Observation

@MainActor
@Observable
public final class MediaController {
    public let source: any MediaSource
    public private(set) var nowPlaying: NowPlaying?
    public private(set) var artwork: Data?
    public private(set) var tint: PillTint?
    public private(set) var isSourceRunning = false
    public private(set) var errorMessage: String?
    public var showsPill: Bool {
        didSet { updatePill() }
    }
    public var onPillChange: (PillStatus?) -> Void = { _ in }

    private let playingInterval: Duration
    private let pausedInterval: Duration
    private var pollTask: Task<Void, Never>?
    private var changeTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var artworkURL: URL?

    public init(source: any MediaSource, showsPill: Bool = true, playingInterval: Duration = .seconds(1), pausedInterval: Duration = .seconds(3)) {
        self.source = source
        self.showsPill = showsPill
        self.playingInterval = playingInterval
        self.pausedInterval = pausedInterval
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
            for await _ in source.stateChanges {
                guard let self else { return }
                await refresh()
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        changeTask?.cancel()
        pollTask = nil
        changeTask = nil
        nowPlaying = nil
        updateArtwork(for: nil)
        updatePill()
    }

    public func refresh() async {
        isSourceRunning = source.isRunning
        guard isSourceRunning else {
            nowPlaying = nil
            errorMessage = nil
            updateArtwork(for: nil)
            updatePill()
            return
        }
        do {
            nowPlaying = try await source.nowPlaying()
            errorMessage = nil
        } catch {
            nowPlaying = nil
            errorMessage = error.localizedDescription
        }
        updateArtwork(for: nowPlaying?.artworkURL)
        updatePill()
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
        do {
            try await command(source)
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
    }

    private func updateArtwork(for url: URL?) {
        guard url != artworkURL else { return }
        artworkURL = url
        artworkTask?.cancel()
        artwork = nil
        tint = nil
        guard let url else { return }
        artworkTask = Task { [weak self] in
            guard let data = try? await URLSession.shared.data(from: url).0, !Task.isCancelled else { return }
            let tint = await Task.detached { ArtworkPalette.tint(for: data) }.value
            guard let self, !Task.isCancelled, artworkURL == url else { return }
            artwork = data
            self.tint = tint
            updatePill()
        }
    }

    private func updatePill() {
        guard showsPill, let nowPlaying, nowPlaying.isPlaying else {
            onPillChange(nil)
            return
        }
        onPillChange(PillStatus(text: "\(nowPlaying.title) · \(nowPlaying.artist)", systemImage: "music.note", priority: .ambient, artwork: artwork, tint: tint))
    }
}
