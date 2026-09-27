import IsletCore
import SwiftUI

@MainActor
public final class MediaPlugin: IsletPlugin {
    public static let manifest = PluginManifest(id: "islet.media", displayName: "Media", systemImage: "music.note")
    static let contentSize = CGSize(width: 420, height: 160)

    private static let showsPillKey = "showsPill"

    private let context: PluginContext
    private let controller: MediaController

    public init(context: PluginContext) {
        self.context = context
        context.contentSize = Self.contentSize
        controller = MediaController(source: SpotifySource(), showsPill: context.settings.value(forKey: Self.showsPillKey) ?? true)
        controller.onPillChange = { [context] status in context.pillStatus = status }
        controller.onShowsPillChange = { [context] shows in context.settings.set(shows, forKey: Self.showsPillKey) }
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
        AnyView(MediaSettings(controller: controller))
    }
}

private struct MediaSettings: View {
    @Bindable var controller: MediaController

    var body: some View {
        Form {
            Section {
                Toggle("Show the current track in the collapsed notch", isOn: $controller.showsPill)
            } footer: {
                Text("Islet needs permission to control Spotify. macOS asks for it the first time the plugin reads what's playing.")
            }
        }
    }
}
