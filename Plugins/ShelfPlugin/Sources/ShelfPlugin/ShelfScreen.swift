import AppKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct ShelfScreen: View {
    let store: ShelfStore
    @State private var isTargeted = false
    @State private var selection = ShelfSelection()
    @State private var quickLookURL: URL?
    @State private var quickLookItems: [URL] = []
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            if store.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 26))
                    Text("Drop files here")
                }
                .foregroundStyle(.secondary)
            } else {
                GeometryReader { geometry in
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: ShelfPlugin.itemSpacing) {
                            ForEach(store.items) { item in
                                ShelfItemView(
                                    item: item,
                                    isSelected: selection.contains(item.id),
                                    onSelect: { select(item.id) },
                                    onRemove: { store.remove(item.id) },
                                    targets: actionTargets(for: item),
                                    onOpen: open,
                                    onQuickLook: showQuickLook,
                                    onShowInFinder: showInFinder,
                                    onRemoveTargets: remove
                                )
                            }
                        }
                        .padding(ShelfPlugin.listPadding)
                        .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
                        .background {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { selection.clear() }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.space) {
            let items = selectedItems
            guard !items.isEmpty else { return .ignored }
            showQuickLook(items)
            return .handled
        }
        .onAppear { store.refreshReachability() }
        .onChange(of: store.items.map { $0.id }) { _, order in
            let present = Set(order)
            var removed = Array(selection.ids.subtracting(present))
            if let anchor = selection.anchor, !present.contains(anchor) {
                removed.append(anchor)
            }
            selection.remove(removed)
            let urls = Set(store.items.map(\.url))
            quickLookItems.removeAll { !urls.contains($0) }
            if let quickLookURL, !urls.contains(quickLookURL) {
                self.quickLookURL = quickLookItems.first
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(isTargeted ? .white : .white.opacity(0.15))
        )
        .onDrop(of: ShelfPlugin.acceptedTypes, isTargeted: $isTargeted) { providers in
            Task { @MainActor in
                await handleDrop(providers)
            }
            return true
        }
        .contextMenu {
            Menu("Clear Shelf") {
                Button("Remove All \(store.items.count) Items", role: .destructive) { store.removeAll() }
            }
            .disabled(store.items.isEmpty)
        }
        .quickLookPreview($quickLookURL, in: quickLookItems)
    }

    private var selectedItems: [ShelfItem] {
        store.items.filter { selection.contains($0.id) }
    }

    private func select(_ id: ShelfItem.ID) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            selection.commandClick(id)
        } else if flags.contains(.shift) {
            selection.shiftClick(id, displayOrder: store.items.map(\.id))
        } else {
            selection.click(id)
        }
        isFocused = true
    }

    private func actionTargets(for item: ShelfItem) -> [ShelfItem] {
        if selection.contains(item.id) {
            selectedItems
        } else {
            [item]
        }
    }

    private func open(_ items: [ShelfItem]) {
        for item in items {
            NSWorkspace.shared.open(item.url)
        }
    }

    private func showQuickLook(_ items: [ShelfItem]) {
        let urls = items.map(\.url)
        guard let first = urls.first else { return }
        quickLookItems = urls
        quickLookURL = first
    }

    private func showInFinder(_ items: [ShelfItem]) {
        NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url))
    }

    private func remove(_ items: [ShelfItem]) {
        for item in items {
            store.remove(item.id)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) async {
        var fileURLs: [URL] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                if let url = await loadURL(from: provider) {
                    fileURLs.append(url)
                }
            } else if let image = await loadImage(from: provider) {
                store.addImage(data: image.data, fileExtension: image.fileExtension)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                      let url = await loadURL(from: provider),
                      let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                store.addLink(url)
            } else if provider.canLoadObject(ofClass: String.self), let text = await loadText(from: provider) {
                store.addText(text)
            }
        }
        await store.add(fileURLs)
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                continuation.resume(returning: text)
            }
        }
    }

    private func loadImage(from provider: NSItemProvider) async -> (data: Data, fileExtension: String)? {
        guard let identifier = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }),
              let type = UTType(identifier)
        else { return nil }
        let data: Data? = await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
        guard let data else { return nil }
        if let fileExtension = type.preferredFilenameExtension, [UTType.png, .jpeg, .gif, .heic, .webP].contains(type) {
            return (data, fileExtension)
        }
        let png = await Task.detached { NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) }.value
        return png.map { ($0, "png") }
    }
}

private struct ShelfItemView: View {
    let item: ShelfItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void
    let targets: [ShelfItem]
    let onOpen: ([ShelfItem]) -> Void
    let onQuickLook: ([ShelfItem]) -> Void
    let onShowInFinder: ([ShelfItem]) -> Void
    let onRemoveTargets: ([ShelfItem]) -> Void
    @State private var isHovering = false
    @State private var icon: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Color.clear
                }
            }
            .frame(width: 44, height: 44)
            .task(id: item.url) {
                let url = item.url
                icon = await Task.detached { NSWorkspace.shared.icon(forFile: url.path) }.value
            }
            Text(item.label)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: ShelfPlugin.itemWidth - 2 * ShelfPlugin.itemPadding)
        }
        .padding(ShelfPlugin.itemPadding)
        .frame(width: ShelfPlugin.itemWidth, height: ShelfPlugin.itemHeight, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? .white.opacity(0.2) : .white.opacity(isHovering ? 0.12 : 0))
        )
        .opacity(item.isReachable ? 1 : 0.4)
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .accessibilityLabel("Remove from Shelf")
            }
        }
        .onHover { isHovering = $0 }
        .onTapGesture { onSelect() }
        .onDrag {
            isHovering = false
            return NSItemProvider(object: item.url as NSURL)
        }
        .contextMenu {
            Button("Open") { onOpen(targets) }
            Button("Quick Look") { onQuickLook(targets) }
            Button("Show in Finder") { onShowInFinder(targets) }
            ShareLink(items: targets.map(\.url))
            Divider()
            Button("Remove from Shelf", role: .destructive) { onRemoveTargets(targets) }
        }
        .help(item.url.path)
    }
}
