import IsletCore
import SwiftUI

@MainActor
public final class DownloadsPlugin: IsletPlugin {
    public static let manifest = PluginManifest(id: "islet.downloads", displayName: "Downloads", systemImage: "arrow.down.circle", summary: "Progress of your downloads and the latest files, ready to drag anywhere.", tint: .cyan)
    static let contentWidth: CGFloat = 380
    static let contentPadding: CGFloat = 12
    static let activeRowHeight: CGFloat = 40
    static let recentRowHeight: CGFloat = 32
    static let rowSpacing: CGFloat = 4
    static let sectionSpacing: CGFloat = 12
    static let maxListHeight: CGFloat = 320
    static let emptyHeight: CGFloat = 72
    static let deniedHeight: CGFloat = 96
    static let doneTint = Color.Resolved(red: 0.25, green: 0.55, blue: 1)
    static let remainingTint = Color.Resolved(red: 0.42, green: 0.42, blue: 0.45)

    static func contentSize(activeCount: Int, recentCount: Int, accessDenied: Bool) -> CGSize {
        let list: CGFloat
        if accessDenied {
            list = deniedHeight
        } else {
            let rows = rowsHeight(activeCount, rowHeight: activeRowHeight)
                + rowsHeight(recentCount, rowHeight: recentRowHeight)
                + (activeCount > 0 && recentCount > 0 ? sectionSpacing : 0)
            list = rows == 0 ? emptyHeight : min(rows, maxListHeight)
        }
        return CGSize(width: contentWidth, height: 2 * contentPadding + list)
    }

    private static func rowsHeight(_ count: Int, rowHeight: CGFloat) -> CGFloat {
        CGFloat(count) * rowHeight + CGFloat(max(count - 1, 0)) * rowSpacing
    }

    static func pillStatus(for downloads: [ActiveDownload]) -> PillStatus? {
        guard let first = downloads.first else { return nil }
        let fractions = downloads.compactMap(\.fraction)
        let combined = fractions.count == downloads.count ? fractions.reduce(0, +) / Double(fractions.count) : nil
        let text: String
        if downloads.count > 1 {
            text = "\(downloads.count) downloads"
        } else if first.fraction == nil, let bytes = first.bytes {
            text = "\(first.name) · \(formatted(bytes: bytes))"
        } else {
            text = first.name
        }
        return PillStatus(text: text, systemImage: manifest.systemImage, priority: .info, ring: combined.map(ring))
    }

    static func ring(_ fraction: Double) -> PillStatus.Ring {
        PillStatus.Ring(segments: [
            .init(value: fraction, tint: doneTint),
            .init(value: 1 - fraction, tint: remainingTint),
        ])
    }

    static func announcement(for finished: FinishedDownload) -> PillAnnouncement {
        let text = finished.names.count == 1 ? "\(finished.names[0]) downloaded" : "\(finished.names.count) files downloaded"
        return PillAnnouncement(text: text, systemImage: "arrow.down.circle.fill", tint: doneTint, priority: .info)
    }

    static func formatted(bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    let recent: RecentDownloads
    let monitor: DownloadMonitor

    public convenience init(context: PluginContext) {
        self.init(context: context, folder: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0])
    }

    init(context: PluginContext, folder: URL) {
        let recent = RecentDownloads(directory: context.storageDirectory, logger: context.logger)
        let monitor = DownloadMonitor(folder: folder, recent: recent, logger: context.logger)
        self.recent = recent
        self.monitor = monitor
        context.derive(\.contentSize) {
            Self.contentSize(activeCount: monitor.downloads.count, recentCount: recent.items.count, accessDenied: monitor.accessDenied)
        }
        context.derive(\.pillStatus) { Self.pillStatus(for: monitor.downloads) }
        context.observe({ monitor.lastFinished }) { [unowned context] finished in
            if let finished {
                context.announce(Self.announcement(for: finished))
            }
        }
        context.observe({ [unowned context] in context.isScreenVisible }) { visible in
            guard visible else { return }
            monitor.rescan()
            recent.refresh()
        }
    }

    public func activate() async throws {
        recent.load()
        monitor.start()
    }

    public func deactivate() async {
        monitor.stop()
    }

    public func makeScreen() -> AnyView {
        AnyView(DownloadsScreen(monitor: monitor, recent: recent))
    }
}
