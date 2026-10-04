import AppKit
import IsletCore
import SwiftUI

@MainActor
public final class MediaPlugin: IsletPlugin {
    public static let manifest = PluginManifest(id: "islet.media", displayName: "Media", systemImage: "music.note")
    static let contentWidth: CGFloat = 420
    static let contentPadding: CGFloat = 12
    static let nowPlayingHeight: CGFloat = 136
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
    static let playerKey = "player"

    private let context: PluginContext
    let controller: MediaController
    let outputs = AudioOutputs()
    private(set) var player: MediaPlayer

    public init(context: PluginContext) {
        self.context = context
        let stored = MediaPlayer(setting: context.settings.value(forKey: Self.playerKey))
        player = MediaPlayer.offered().contains(stored) ? stored : .automatic
        let controller = MediaController(sources: player.makeSources(), showsPill: context.settings.value(forKey: Self.showsPillKey) ?? true)
        self.controller = controller
        controller.onCommandError = { [unowned context] message in
            context.announce(PillAnnouncement(text: message, systemImage: "exclamationmark.triangle.fill"))
        }
        context.derive(\.pillStatus) { controller.pillStatus }
        context.derive(\.contentSize) {
            Self.contentSize(isBrowsing: controller.isBrowsingPlaylists, playlistCount: controller.playlists.count)
        }
        context.observe({ controller.showsPill }) { [settings = context.settings] in settings.set($0, forKey: Self.showsPillKey) }
        context.observe({ [unowned context] in context.isScreenVisible }) { controller.isScreenVisible = $0 }
    }

    public func activate() async throws {
        outputs.start()
        controller.start()
    }

    public func deactivate() async {
        controller.stop()
        outputs.stop()
    }

    public func makeScreen() -> AnyView {
        AnyView(MediaScreen(controller: controller, outputs: outputs))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(MediaSettings(controller: controller, player: player) { [weak self] player in
            self?.select(player)
        })
    }

    func select(_ player: MediaPlayer) {
        guard player != self.player else { return }
        self.player = player
        context.settings.set(player.rawValue, forKey: Self.playerKey)
        controller.replaceSources(player.makeSources())
    }
}

enum MediaPlayer: String, CaseIterable, Identifiable {
    case automatic
    case spotify
    case music

    init(setting: String?) {
        self = setting.flatMap(Self.init(rawValue:)) ?? .automatic
    }

    var id: Self { self }

    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .spotify: "Spotify"
        case .music: "Music"
        }
    }

    static func isInstalled(_ bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    func makeSources(installed: (String) -> Bool = Self.isInstalled) -> [any MediaSource] {
        let candidates: [any MediaSource]
        switch self {
        case .automatic:
            candidates = [SpotifySource(), MusicSource()]
        case .spotify:
            candidates = [SpotifySource()]
        case .music:
            candidates = [MusicSource()]
        }
        return candidates.filter { installed($0.bundleIdentifier) }
    }

    static func offered(installed: (String) -> Bool = Self.isInstalled) -> [MediaPlayer] {
        [.automatic] + [.spotify, .music].filter { !$0.makeSources(installed: installed).isEmpty }
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
                    ForEach(MediaPlayer.offered()) { player in
                        Text(player.displayName).tag(player)
                    }
                }
                .onChange(of: player) { onPlayerChange(player) }
                Toggle("Show the current track in the collapsed notch", isOn: $controller.showsPill)
            } footer: {
                Text("Islet needs permission to control \(permissionName). macOS asks for it the first time the plugin reads what's playing.")
            }
        }
    }

    private var permissionName: String {
        player == .automatic ? "Spotify or Music" : player.displayName
    }
}
