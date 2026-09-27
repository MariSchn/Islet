import SwiftUI

struct MediaScreen: View {
    let controller: MediaController

    var body: some View {
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
                } else if let error = controller.errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Nothing playing")
                        .foregroundStyle(.secondary)
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

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 12) {
                ArtworkView(image: controller.artwork)
                    .frame(width: proxy.size.height, height: proxy.size.height)
                VStack(alignment: .leading, spacing: 2) {
                    Text(nowPlaying.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(nowPlaying.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    HStack(spacing: 28) {
                        TransportButton(systemImage: "backward.fill", size: 17) { await controller.previousTrack() }
                        TransportButton(systemImage: nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 24) { await controller.playPause() }
                        TransportButton(systemImage: "forward.fill", size: 17) { await controller.nextTrack() }
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
