import IsletCore
import SwiftUI

@MainActor
public final class ShelfPlugin: IsletPlugin {
    public static let manifest = PluginManifest(id: "islet.shelf", displayName: "Shelf", systemImage: "tray.full")
    static let contentPadding: CGFloat = 12
    static let listPadding: CGFloat = 4
    static let itemWidth: CGFloat = 84
    static let itemHeight: CGFloat = 88
    static let itemPadding: CGFloat = 6
    static let itemSpacing: CGFloat = 8
    static let minContentWidth: CGFloat = 360
    static let maxContentWidth: CGFloat = 520

    static func contentSize(forItemCount count: Int) -> CGSize {
        let items = CGFloat(count) * itemWidth + CGFloat(max(count - 1, 0)) * itemSpacing
        let width = 2 * contentPadding + 2 * listPadding + items
        return CGSize(
            width: min(max(width, minContentWidth), maxContentWidth),
            height: 2 * contentPadding + 2 * listPadding + itemHeight
        )
    }

    let store: ShelfStore

    public init(context: PluginContext) {
        store = ShelfStore(directory: context.storageDirectory, logger: context.logger)
        context.derive(\.contentSize) { [store] in Self.contentSize(forItemCount: store.items.count) }
    }

    public func activate() async throws {
        store.load()
    }

    public func makeScreen() -> AnyView {
        AnyView(ShelfScreen(store: store))
    }

    public var acceptsFileDrops: Bool { true }
}
