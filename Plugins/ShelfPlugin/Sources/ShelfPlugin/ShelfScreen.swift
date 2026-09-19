import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ShelfScreen: View {
    let store: ShelfStore
    @State private var isTargeted = false

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
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(store.items) { item in
                            ShelfItemView(item: item) { store.remove(item.id) }
                        }
                    }
                    .padding(4)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(isTargeted ? .white : .white.opacity(0.15))
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task { @MainActor in
                let urls = await loadFileURLs(from: providers)
                store.add(urls)
            }
            return true
        }
        .contextMenu {
            Button("Clear Shelf", role: .destructive) { store.removeAll() }
                .disabled(store.items.isEmpty)
        }
    }

    private func loadFileURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    continuation.resume(returning: url)
                }
            }
            if let url {
                urls.append(url)
            }
        }
        return urls
    }
}

private struct ShelfItemView: View {
    let item: ShelfItem
    let onRemove: () -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 44, height: 44)
            Text(item.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 72)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(isHovering ? 0.12 : 0))
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
            }
        }
        .onHover { isHovering = $0 }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(item.url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Divider()
            Button("Remove from Shelf", role: .destructive, action: onRemove)
        }
        .help(item.url.path)
    }
}
