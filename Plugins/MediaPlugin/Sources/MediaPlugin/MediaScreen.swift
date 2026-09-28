import SwiftUI

struct MediaScreen: View {
    let controller: MediaController

    var body: some View {
        VStack(spacing: MediaPlugin.browserSpacing) {
            content
                .frame(height: MediaPlugin.nowPlayingHeight)
            if controller.isBrowsingPlaylists {
                PlaylistBrowser(controller: controller)
                    .frame(height: MediaPlugin.browserHeight(playlistCount: controller.playlists.count), alignment: .top)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let nowPlaying = controller.nowPlaying {
            NowPlayingView(nowPlaying: nowPlaying, controller: controller)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "music.note")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                if !controller.isSourceRunning {
                    Text("\(controller.source.displayName) is not running")
                        .foregroundStyle(.secondary)
                    Button("Open \(controller.source.displayName)") { controller.launchSource() }
                        .buttonStyle(.bordered)
                } else {
                    if let error = controller.errorMessage {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    } else {
                        Text("Nothing playing")
                            .foregroundStyle(.secondary)
                    }
                    if controller.capabilities.canBrowsePlaylists, !controller.isBrowsingPlaylists {
                        Button("Browse Playlists") { Task { await controller.showPlaylists() } }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct NowPlayingView: View {
    let nowPlaying: NowPlaying
    let controller: MediaController

    private var tint: Color {
        controller.tint.map(Color.init) ?? .white
    }

    private var capabilities: MediaCapabilities {
        controller.capabilities
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 12) {
                ArtworkView(image: controller.artwork)
                    .frame(width: proxy.size.height, height: proxy.size.height)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(nowPlaying.title)
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(1)
                            Text(nowPlaying.artist)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if capabilities.canBrowsePlaylists {
                            ToggleButton(systemImage: "music.note.list", isOn: controller.isBrowsingPlaylists, tint: tint, help: "Playlists") {
                                await controller.togglePlaylists()
                            }
                        }
                    }
                    Spacer(minLength: 4)
                    HStack(spacing: 0) {
                        if capabilities.canShuffle {
                            ToggleButton(systemImage: "shuffle", isOn: nowPlaying.isShuffling, tint: tint, help: "Shuffle") {
                                await controller.toggleShuffle()
                            }
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 24) {
                            TransportButton(systemImage: "backward.fill", size: 17) { await controller.previousTrack() }
                            TransportButton(systemImage: nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 24) { await controller.playPause() }
                            TransportButton(systemImage: "forward.fill", size: 17) { await controller.nextTrack() }
                        }
                        Spacer(minLength: 0)
                        if capabilities.canRepeat {
                            ToggleButton(systemImage: nowPlaying.repeatMode == .one ? "repeat.1" : "repeat", isOn: nowPlaying.repeatMode != .off, tint: tint, help: "Repeat") {
                                await controller.cycleRepeatMode()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    Spacer(minLength: 4)
                    Timeline(nowPlaying: nowPlaying, tint: tint) { position in
                        await controller.seek(to: position)
                    }
                }
            }
        }
    }
}

private struct ArtworkView: View {
    let image: CGImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.white.opacity(0.1))
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct Timeline: View {
    let nowPlaying: NowPlaying
    let tint: Color
    let onSeek: (TimeInterval) async -> Void
    @State private var isHovering = false
    @State private var scrubFraction: Double?
    @State private var seekTask: Task<Void, Never>?

    private var isActive: Bool { isHovering || scrubFraction != nil }
    private var fraction: Double { scrubFraction ?? nowPlaying.progress }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let knobX = width * fraction
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25)).frame(height: 4)
                    Capsule().fill(isActive ? tint : .white).frame(width: knobX, height: 4)
                    if isActive {
                        Circle()
                            .fill(.white)
                            .frame(width: 12, height: 12)
                            .offset(x: knobX - 6)
                    }
                    if let scrubFraction {
                        Text(timestamp(scrubFraction * nowPlaying.duration))
                            .font(.caption.monospacedDigit().weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .fixedSize()
                            .offset(x: min(max(knobX - 24, 0), width - 48), y: -26)
                    }
                }
                .frame(height: proxy.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in scrubFraction = fraction(at: value.location.x, in: width) }
                        .onEnded { value in
                            let target = fraction(at: value.location.x, in: width)
                            scrubFraction = target
                            seekTask?.cancel()
                            seekTask = Task {
                                await onSeek(target * nowPlaying.duration)
                                guard !Task.isCancelled else { return }
                                scrubFraction = nil
                            }
                        }
                )
            }
            .frame(height: 14)
            .onHover { isHovering = $0 }
            HStack {
                Text(timestamp(fraction * nowPlaying.duration))
                Spacer()
                Text(timestamp(nowPlaying.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .animation(.easeOut(duration: 0.15), value: isActive)
    }

    private func fraction(at x: CGFloat, in width: CGFloat) -> Double {
        guard width > 0 else { return nowPlaying.progress }
        return min(max(x / width, 0), 1)
    }

    private func timestamp(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }
}

private struct TransportButton: View {
    let systemImage: String
    let size: CGFloat
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ToggleButton: View {
    let systemImage: String
    let isOn: Bool
    let tint: Color
    let help: String
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isOn ? tint : .white.opacity(0.45))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct PlaylistBrowser: View {
    let controller: MediaController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let error = controller.playlistError, !controller.playlists.isEmpty {
                    Text(error)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                } else {
                    Text("Playlists")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    controller.hidePlaylists()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: MediaPlugin.browserHeaderHeight, height: MediaPlugin.browserHeaderHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Playlists")
            }
            .frame(height: MediaPlugin.browserHeaderHeight)
            if controller.isLoadingPlaylists {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .frame(height: MediaPlugin.playlistRowHeight)
            } else if controller.playlists.isEmpty, let error = controller.playlistError {
                message(error, color: .orange)
            } else if controller.playlists.isEmpty {
                message("No playlists", color: .secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(controller.playlists) { playlist in
                            PlaylistRow(playlist: playlist) { await controller.play(playlist) }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }

    private func message(_ text: String, color: some ShapeStyle) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: MediaPlugin.playlistRowHeight)
    }
}

private struct PlaylistRow: View {
    let playlist: MediaPlaylist
    let action: () async -> Void
    @State private var isHovering = false

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(playlist.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "play.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .opacity(isHovering ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .frame(height: MediaPlugin.playlistRowHeight)
            .background(.white.opacity(isHovering ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
