import IsletCore
import SwiftUI

@MainActor
public final class MediaPlugin: IsletPlugin {
    public static let manifest = PluginManifest(id: "islet.media", displayName: "Media", systemImage: "music.note")
    static let contentWidth: CGFloat = 520
    static let contentPadding: CGFloat = 12
    static let nowPlayingHeight: CGFloat = 196
    static let browserSpacing: CGFloat = 10
    static let browserHeaderHeight: CGFloat = 20
    static let playlistRowHeight: CGFloat = 28
    static let maxVisiblePlaylistRows = 5

    static func contentSize(isBrowsing: Bool, playlistCount: Int) -> CGSize {
        let browser = isBrowsing ? browserSpacing + browserHeight(playlistCount: playlistCount) : 0
        return CGSize(width: contentWidth, height: 2 * contentPadding + nowPlayingHeight + browser)
    }

    static func browserHeight(playlistCount: Int) -> CGFloat {
        browserHeaderHeight + CGFloat(min(max(playlistCount, 1), maxVisiblePlaylistRows)) * playlistRowHeight
    }

    private static let showsPillKey = "showsPill"
    private static let playerKey = "player"

    private let context: PluginContext
    private let controller: MediaController
    private var player: MediaPlayer

    public init(context: PluginContext) {
        self.context = context
        player = (context.settings.value(forKey: Self.playerKey) as String?).flatMap(MediaPlayer.init(rawValue:)) ?? .spotify
        controller = MediaController(source: player.makeSource(), showsPill: context.settings.value(forKey: Self.showsPillKey) ?? true)
        controller.onPillChange = { [context] status in context.pillStatus = status }
        controller.onShowsPillChange = { [context] shows in context.settings.set(shows, forKey: Self.showsPillKey) }
        controller.onLayoutChange = { [context, controller] in
            context.contentSize = Self.contentSize(isBrowsing: controller.isBrowsingPlaylists, playlistCount: controller.playlists.count)
        }
        controller.onLayoutChange()
    }

    public func activate() async throws {
        controller.start()
    }

    public func deactivate() async {
        controller.stop()
    }

    public func makeScreen() -> AnyView {
        AnyView(MediaScreen(controller: controller))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(MediaSettings(controller: controller, player: player) { [weak self] player in
            self?.select(player)
        })
    }

    private func select(_ player: MediaPlayer) {
        guard player != self.player else { return }
        self.player = player
        context.settings.set(player.rawValue, forKey: Self.playerKey)
        controller.replaceSource(player.makeSource())
    }
}

enum MediaPlayer: String, CaseIterable, Identifiable {
    case spotify
    case music

    var id: Self { self }

    var displayName: String {
        switch self {
        case .spotify: "Spotify"
        case .music: "Music"
        }
    }

    func makeSource() -> any MediaSource {
        switch self {
        case .spotify: SpotifySource()
        case .music: MusicSource()
        }
    }
}

private struct MediaSettings: View {
    @Bindable var controller: MediaController
    @State var player: MediaPlayer
    let onPlayerChange: (MediaPlayer) -> Void

    var body: some View {
        Form {
            Section {
                Picker("Player", selection: $player) {
                    ForEach(MediaPlayer.allCases) { player in
                        Text(player.displayName).tag(player)
                    }
                }
                .onChange(of: player) { onPlayerChange(player) }
                Toggle("Show the current track in the collapsed notch", isOn: $controller.showsPill)
            } footer: {
                Text("Islet needs permission to control \(player.displayName). macOS asks for it the first time the plugin reads what's playing.")
            }
        }
    }
}
