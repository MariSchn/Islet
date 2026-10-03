import AppKit
import SwiftUI

struct DownloadsScreen: View {
    let monitor: DownloadMonitor
    let recent: RecentDownloads

    var body: some View {
        Group {
            if monitor.accessDenied {
                AccessDeniedView()
            } else if monitor.downloads.isEmpty && recent.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 22))
                    Text("No recent downloads")
                }
                .foregroundStyle(.secondary)
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: DownloadsPlugin.sectionSpacing) {
                        if !monitor.downloads.isEmpty {
                            VStack(spacing: DownloadsPlugin.rowSpacing) {
                                ForEach(monitor.downloads) { download in
                                    ActiveDownloadRow(download: download)
                                }
                            }
                        }
                        if !recent.items.isEmpty {
                            VStack(spacing: DownloadsPlugin.rowSpacing) {
                                ForEach(recent.items) { item in
                                    RecentDownloadRow(item: item) { recent.remove(item.id) }
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ActiveDownloadRow: View {
    let download: ActiveDownload

    private var detail: String {
        let size = download.bytes.map { DownloadsPlugin.formatted(bytes: $0) }
        let percent = download.fraction.map { $0.formatted(.percent.precision(.fractionLength(0))) }
        return [percent, size].compactMap(\.self).joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(download.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(detail)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            Group {
                if let fraction = download.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
            }
            .progressViewStyle(.linear)
            .tint(Color(DownloadsPlugin.doneTint))
        }
        .padding(.horizontal, 8)
        .frame(height: DownloadsPlugin.activeRowHeight)
    }
}

private struct RecentDownloadRow: View {
    let item: RecentDownload
    let onRemove: () -> Void
    @State private var isHovering = false
    @State private var icon: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Color.clear
                }
            }
            .frame(width: 24, height: 24)
            .task(id: item.url) {
                let url = item.url
                icon = await Task.detached { NSWorkspace.shared.icon(forFile: url.path) }.value
            }
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if let bytes = item.bytes {
                Text(DownloadsPlugin.formatted(bytes: bytes))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .frame(height: DownloadsPlugin.recentRowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(isHovering ? 0.1 : 0))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onDrag {
            isHovering = false
            return NSItemProvider(object: item.url as NSURL)
        }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(item.url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Divider()
            Button("Remove from List", role: .destructive, action: onRemove)
        }
        .help(item.url.path)
    }
}

private struct AccessDeniedView: View {
    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
            Text("Islet can't read your Downloads folder")
            Button("Open System Settings") {
                if let url = Self.settingsURL {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
        }
    }
}
