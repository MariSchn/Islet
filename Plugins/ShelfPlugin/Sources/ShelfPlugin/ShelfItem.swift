import Foundation

struct ShelfItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    private(set) var url: URL
    let addedAt: Date
    var isReachable: Bool
    private var bookmark: Data?

    init(url: URL, addedAt: Date = .now) {
        self.id = UUID()
        self.url = Self.canonical(url)
        self.addedAt = addedAt
        self.isReachable = Self.checkReachable(self.url)
        self.bookmark = try? url.bookmarkData(options: .minimalBookmark)
    }

    var name: String { url.lastPathComponent }

    static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func checkReachable(_ url: URL) -> Bool {
        (try? url.checkResourceIsReachable()) == true
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
