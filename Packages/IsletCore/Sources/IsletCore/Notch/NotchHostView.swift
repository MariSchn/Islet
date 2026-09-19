import SwiftUI

public struct NotchHostView: View {
    private let registry: PluginRegistry
    private let openSettings: () -> Void

    public init(registry: PluginRegistry, openSettings: @escaping () -> Void) {
        self.registry = registry
        self.openSettings = openSettings
    }

    public var body: some View {
        VStack(spacing: 10) {
            NotchTabBar(registry: registry, openSettings: openSettings)
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
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(registry.enabledEntries) { entry in
                NotchBarButton(systemImage: entry.manifest.systemImage, isSelected: entry.id == registry.selectedID) {
                    registry.select(entry.id)
                }
                .help(entry.manifest.displayName)
            }
            Spacer(minLength: 0)
            NotchBarButton(systemImage: "gearshape", isSelected: false, action: openSettings)
                .help("Islet Settings")
        }
        .frame(maxWidth: .infinity)
    }
}

private struct NotchBarButton: View {
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isSelected ? .white.opacity(0.18) : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}
