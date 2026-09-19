import Foundation

public struct ShelfItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public private(set) var url: URL
    public let addedAt: Date
    private var bookmark: Data?

    public init(url: URL, addedAt: Date = .now) {
        self.id = UUID()
        self.url = url.standardizedFileURL
        self.addedAt = addedAt
        self.bookmark = try? url.bookmarkData(options: .minimalBookmark)
    }

    public var name: String { url.lastPathComponent }

    public var isReachable: Bool {
        (try? url.checkResourceIsReachable()) == true
    }

    mutating func resolveBookmark() {
        guard let bookmark else { return }
        var stale = false
        if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], bookmarkDataIsStale: &stale) {
            url = resolved.standardizedFileURL
            if stale {
                self.bookmark = try? url.bookmarkData(options: .minimalBookmark)
            }
        }
    }
}
