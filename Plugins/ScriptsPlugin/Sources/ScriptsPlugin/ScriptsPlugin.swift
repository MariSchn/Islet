import IsletCore
import SwiftUI

@MainActor
public final class ScriptsPlugin: IsletPlugin {
    public static let manifest = PluginManifest(id: "islet.scripts", displayName: "Scripts", systemImage: "bolt.fill", summary: "Show the progress of your own scripts and commands.", tint: .mint)

    static let width: CGFloat = 420
    static let contentPadding: CGFloat = 12
    static let rowHeight: CGFloat = 36
    static let maxVisibleRows = 5
    static let emptyHeight: CGFloat = 80
    private static let tokenKey = "token"

    let controller: ScriptsController

    public static func contentSize(activityCount: Int) -> CGSize {
        let rows = min(activityCount, maxVisibleRows)
        return CGSize(width: width, height: rows == 0 ? emptyHeight : 2 * contentPadding + CGFloat(rows) * rowHeight)
    }

    public init(context: PluginContext) {
        let settings = context.settings
        let token: String
        if let stored: String = settings.value(forKey: Self.tokenKey) {
            token = stored
        } else {
            token = ScriptsController.makeToken()
            settings.set(token, forKey: Self.tokenKey)
        }
        let controller = ScriptsController(
            token: token,
            storageDirectory: context.storageDirectory,
            announce: { [weak context] in context?.announce($0) },
            saveToken: { settings.set($0, forKey: Self.tokenKey) },
            logger: context.logger
        )
        self.controller = controller
        context.derive(\.pillStatus) { controller.store.pillStatus }
        context.derive(\.contentSize) { Self.contentSize(activityCount: controller.store.activities.count) }
    }

    public func activate() async throws {
        await controller.start()
    }

    public func deactivate() async {
        await controller.stop()
    }

    public func makeScreen() -> AnyView {
        AnyView(ScriptsScreen(controller: controller))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(ScriptsSettings(controller: controller))
    }
}
