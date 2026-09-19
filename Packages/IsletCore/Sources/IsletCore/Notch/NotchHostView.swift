import SwiftUI

public struct NotchHostView: View {
    private let registry: PluginRegistry

    public init(registry: PluginRegistry) {
        self.registry = registry
    }

    public var body: some View {
        VStack(spacing: 10) {
            NotchTabBar(registry: registry)
            if let selected = registry.selectedID, let entry = registry.entry(for: selected) {
                PluginScreen(entry: entry)
                    .id(selected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text("No plugins enabled")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(.white)
    }
}

private struct PluginScreen: View {
    let entry: PluginEntry

    var body: some View {
        switch entry.state {
        case .active:
            entry.screen
        case .failed(let error):
            Label("\(entry.manifest.displayName) failed to start: \(error.localizedDescription)", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .inactive, .activating, .deactivating:
            ProgressView()
                .controlSize(.small)
        }
    }
}

struct NotchTabBar: View {
    let registry: PluginRegistry

    var body: some View {
        HStack(spacing: 4) {
            ForEach(registry.enabledEntries) { entry in
                Button {
                    registry.select(entry.id)
                } label: {
                    Image(systemName: entry.manifest.systemImage)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 30, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(entry.id == registry.selectedID ? .white.opacity(0.18) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .help(entry.manifest.displayName)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
