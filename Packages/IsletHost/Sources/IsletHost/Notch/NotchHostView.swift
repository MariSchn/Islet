import IsletCore
import SwiftUI

public struct NotchHostView: View {
    private let controller: NotchController
    private let registry: PluginRegistry
    private let openSettings: () -> Void

    public init(controller: NotchController, registry: PluginRegistry, openSettings: @escaping () -> Void) {
        self.controller = controller
        self.registry = registry
        self.openSettings = openSettings
    }

    public var body: some View {
        VStack(spacing: 0) {
            NotchNavigationBar(
                registry: registry,
                notchWidth: controller.geometry.notchSize.width,
                sideWidth: controller.navigationSideWidth,
                animation: switchAnimation,
                openSettings: openSettings
            )
            .frame(height: controller.geometry.notchSize.height)
            PluginCarousel(registry: registry, geometry: controller.geometry, animation: switchAnimation)
        }
        .foregroundStyle(.white)
        .environment(\.notchAnimation, switchAnimation)
    }

    private var switchAnimation: Animation {
        controller.animation.animation(expanding: true)
    }
}

private struct PluginCarousel: View {
    let registry: PluginRegistry
    let geometry: NotchGeometry
    let animation: Animation

    private struct Placement: Equatable {
        let id: String
        let size: CGSize
        let offset: CGFloat
    }

    private var placements: [Placement] {
        let entries = registry.enabledEntries
        guard let selectedIndex = entries.firstIndex(where: { $0.id == registry.selectedID }) else { return [] }
        let sizes = entries.map { geometry.contentSize(for: $0.context.contentSize) }
        return entries.indices.map { index in
            let span = index < selectedIndex ? sizes[index..<selectedIndex] : sizes[selectedIndex..<index]
            let distance = span.reduce(0) { $0 + $1.width } + (sizes[index].width - sizes[selectedIndex].width) / 2
            let offset = index < selectedIndex ? -distance : distance
            return Placement(id: entries[index].id, size: sizes[index], offset: offset)
        }
    }

    var body: some View {
        let placements = placements
        ZStack(alignment: .top) {
            if placements.isEmpty {
                Text("No plugins enabled")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            ForEach(placements, id: \.id) { placement in
                if let entry = registry.entry(for: placement.id) {
                    let isSelected = placement.id == registry.selectedID
                    let scale = geometry.contentScale
                    PluginScreen(entry: entry)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(12)
                        .frame(width: placement.size.width / scale, height: placement.size.height / scale)
                        .scaleEffect(scale, anchor: .top)
                        .frame(width: placement.size.width, height: placement.size.height, alignment: .top)
                        .opacity(isSelected ? 1 : 0)
                        .allowsHitTesting(isSelected)
                        .accessibilityHidden(!isSelected)
                        .offset(x: placement.offset)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(animation, value: placements)
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

private struct NotchNavigationBar: View {
    let registry: PluginRegistry
    let notchWidth: CGFloat
    let sideWidth: CGFloat
    let animation: Animation
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            PluginTabCarousel(registry: registry, width: sideWidth, animation: animation)
                .frame(width: sideWidth)
            Color.clear
                .frame(width: notchWidth)
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                NotchBarButton(systemImage: "gearshape", isSelected: false, action: openSettings)
                    .help("Islet Settings")
            }
            .padding(.trailing, 8)
            .frame(width: sideWidth)
        }
    }
}

private struct PluginTabCarousel: View {
    let registry: PluginRegistry
    let width: CGFloat
    let animation: Animation

    private static let step: CGFloat = 34
    private static let fadeWidth: CGFloat = 16
    private static let selectedInset: CGFloat = NotchGeometry.navigationSideMinWidth / 2

    var body: some View {
        let entries = registry.enabledEntries
        let selectedIndex = entries.firstIndex { $0.id == registry.selectedID }
        ZStack {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                let distance = index - (selectedIndex ?? 0)
                let offset = width / 2 - Self.selectedInset + CGFloat(distance) * Self.step
                NotchBarButton(systemImage: entry.manifest.systemImage, isSelected: index == selectedIndex) {
                    registry.select(entry.id)
                }
                .help(entry.manifest.displayName)
                .opacity(index == selectedIndex ? 1 : 0.45)
                .offset(x: offset)
                .allowsHitTesting(abs(offset) <= width / 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .mask(
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: Self.fadeWidth)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: Self.fadeWidth)
            }
        )
        .animation(animation, value: selectedIndex)
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
