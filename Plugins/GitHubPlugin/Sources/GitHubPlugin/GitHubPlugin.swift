import IsletCore
import SwiftUI

@MainActor
public final class GitHubPlugin: IsletPlugin {
    public static let manifest = PluginManifest(id: "islet.github", displayName: "GitHub", systemImage: "arrow.triangle.pull")
    static let contentWidth: CGFloat = 480
    static let contentPadding: CGFloat = 12
    static let messageHeight: CGFloat = 96
    static let sectionHeaderHeight: CGFloat = 18
    static let sectionSpacing: CGFloat = 8
    static let rowHeight: CGFloat = 40
    static let maxVisibleRows = 6

    static func contentSize(for snapshot: GitHubSnapshot?) -> CGSize {
        guard let snapshot, !snapshot.isEmpty else {
            return CGSize(width: contentWidth, height: 2 * contentPadding + messageHeight)
        }
        let sections = [snapshot.mine.count, snapshot.reviewRequested.count].filter { $0 > 0 }
        let rows = min(sections.reduce(0, +), maxVisibleRows)
        let height = 2 * contentPadding
            + CGFloat(sections.count) * sectionHeaderHeight
            + CGFloat(sections.count - 1) * sectionSpacing
            + CGFloat(rows) * rowHeight
        return CGSize(width: contentWidth, height: height)
    }

    static let showsPillKey = "showsPill"

    let controller: GitHubController

    public convenience init(context: PluginContext) {
        self.init(context: context, client: GhClient())
    }

    init(context: PluginContext, client: any GitHubClient, networkUpdates: @escaping NetworkUpdates = NetworkStatus.updates) {
        let settings = context.settings
        let controller = GitHubController(
            client: client,
            showsPill: settings.value(forKey: Self.showsPillKey) ?? true,
            networkUpdates: networkUpdates,
            logger: context.logger
        )
        self.controller = controller
        context.derive(\.contentSize) { Self.contentSize(for: controller.phase.snapshot) }
        context.derive(\.pillStatus) { controller.pillStatus }
        context.observe({ controller.showsPill }) { settings.set($0, forKey: Self.showsPillKey) }
        var previous: GitHubSnapshot?
        context.observe({ controller.phase }) { [unowned context] phase in
            let current = phase.snapshot
            defer { previous = current }
            if let current, let announcement = GitHubChanges.announcement(from: previous, to: current) {
                context.announce(announcement)
            }
        }
        context.observe({ [unowned context] in context.isScreenVisible }) { controller.isScreenVisible = $0 }
    }

    public func activate() async throws {
        controller.start()
    }

    public func deactivate() async {
        controller.stop()
    }

    public func makeScreen() -> AnyView {
        AnyView(GitHubScreen(controller: controller))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(GitHubSettings(controller: controller))
    }
}

private struct GitHubSettings: View {
    @Bindable var controller: GitHubController

    var body: some View {
        Form {
            Section {
                Toggle("Show the closed-notch status", isOn: $controller.showsPill)
            } footer: {
                Text("A ring with the CI state of your pull requests. It turns orange when checks fail or someone requests your review.")
            }
        }
    }
}
