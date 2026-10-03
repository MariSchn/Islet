import Foundation
import Observation
import os

struct RecentDownload: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    private(set) var url: URL
    let finishedAt: Date
    var bytes: Int64?
    private var bookmark: Data?

    init(url: URL, finishedAt: Date = .now) {
        self.id = UUID()
        self.url = Self.canonical(url)
        self.finishedAt = finishedAt
        self.bytes = Self.size(of: self.url)
        self.bookmark = try? self.url.bookmarkData(options: .minimalBookmark)
    }

    var name: String { url.lastPathComponent }

    static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func isReachable(_ url: URL) -> Bool {
        (try? url.checkResourceIsReachable()) == true
    }

    static func size(of url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) }
    }

    mutating func fillMissingDetails() -> Bool {
        var changed = false
        if bytes == nil, let size = Self.size(of: url) {
            bytes = size
            changed = true
        }
        if bookmark == nil, let fresh = try? url.bookmarkData(options: .minimalBookmark) {
            bookmark = fresh
            changed = true
        }
        return changed
    }

    @discardableResult
    mutating func resolveBookmark() -> Bool {
        guard let bookmark else { return false }
        var stale = false
        guard let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], bookmarkDataIsStale: &stale) else {
            return false
        }
        let canonical = Self.canonical(resolved)
        var changed = false
        if canonical != url {
            url = canonical
            changed = true
        }
        if stale, let fresh = try? url.bookmarkData(options: .minimalBookmark) {
            self.bookmark = fresh
            changed = true
        }
        return changed
    }
}

@MainActor
@Observable
final class RecentDownloads {
    static let limit = 8

    private(set) var items: [RecentDownload] = []

    private let fileURL: URL
    private let logger: Logger

    init(directory: URL, logger: Logger = Logger()) {
        fileURL = directory.appending(path: "recent.json")
        self.logger = logger
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        var loaded: [RecentDownload]
        do {
            loaded = try JSONDecoder().decode([RecentDownload].self, from: data)
        } catch {
            logger.error("Could not read \(self.fileURL.path, privacy: .public), keeping it aside: \(error, privacy: .public)")
            try? FileManager.default.moveItem(at: fileURL, to: fileURL.appendingPathExtension("corrupt"))
            return
        }
        var changed = false
        for index in loaded.indices {
            changed = loaded[index].resolveBookmark() || changed
        }
        var reachable = loaded.filter { RecentDownload.isReachable($0.url) }
        changed = changed || reachable.count != loaded.count
        for index in reachable.indices {
            changed = reachable[index].fillMissingDetails() || changed
        }
        items = Array(reachable.prefix(Self.limit))
        if changed || loaded.count > Self.limit {
            save()
        }
    }

    func add(_ url: URL) {
        let item = RecentDownload(url: url)
        items.removeAll { $0.url == item.url }
        items.insert(item, at: 0)
        if items.count > Self.limit {
            items.removeLast(items.count - Self.limit)
        }
        save()
    }

    func remove(_ id: RecentDownload.ID) {
        guard items.contains(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        save()
    }

    func refresh() {
        let snapshot = items.map { ($0.id, $0.url) }
        Task.detached(priority: .utility) { [weak self] in
            let unreachable = Set(snapshot.filter { !RecentDownload.isReachable($0.1) }.map(\.0))
            await self?.apply(unreachable: unreachable)
        }
    }

    private func apply(unreachable: Set<RecentDownload.ID>) {
        var updated = items.filter { !unreachable.contains($0.id) }
        var changed = updated.count != items.count
        for index in updated.indices {
            changed = updated[index].fillMissingDetails() || changed
        }
        guard changed else { return }
        items = updated
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save: \(error, privacy: .public)")
        }
    }
}
