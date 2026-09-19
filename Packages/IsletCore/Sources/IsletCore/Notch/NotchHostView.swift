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
                entry.plugin.makeScreen()
                    .id(selected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text("No plugins enabled")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(.white)
        .colorScheme(.dark)
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
