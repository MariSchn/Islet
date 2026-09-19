import IsletCore
import SwiftUI

@MainActor
public final class ShelfPlugin: IsletPlugin {
    public static let manifest = PluginManifest(id: "islet.shelf", displayName: "Shelf", systemImage: "tray.full")

    private let store: ShelfStore

    public init(context: PluginContext) {
        store = ShelfStore(directory: context.storageDirectory)
    }

    public func activate() async throws {
        store.load()
    }

    public func makeScreen() -> AnyView {
        AnyView(ShelfScreen(store: store))
    }
}
