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

    static let copyModeKey = "copyMode"

    let store: ShelfStore

    public init(context: PluginContext) {
        let store = ShelfStore(directory: context.storageDirectory, logger: context.logger)
        store.copyMode = ShelfCopyMode(stored: context.settings.value(forKey: Self.copyModeKey))
        self.store = store
        context.derive(\.contentSize) { [store] in Self.contentSize(forItemCount: store.items.count) }
        context.observe({ [store] in store.copyMode }) { [settings = context.settings] mode in
            settings.set(mode.rawValue, forKey: Self.copyModeKey)
        }
    }

    public func activate() async throws {
        store.load()
    }

    public func makeScreen() -> AnyView {
        AnyView(ShelfScreen(store: store))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(ShelfSettings(store: store))
    }

    public var acceptsFileDrops: Bool { true }
}

private struct ShelfSettings: View {
    @Bindable var store: ShelfStore

    var body: some View {
        Form {
            Section {
                Picker("Keep a copy of dropped files", selection: $store.copyMode) {
                    ForEach(ShelfCopyMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }
        }
    }
}
