import Foundation

enum ShelfItemKind: String, Codable, Sendable {
    case file, text, link, image
}

struct ShelfItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    private(set) var url: URL
    let addedAt: Date
    var isReachable: Bool
    let ownsFile: Bool
    let sourceURL: URL?
    let kind: ShelfItemKind
    let title: String?
    private var bookmark: Data?

    init(id: UUID = UUID(), url: URL, addedAt: Date = .now, ownsFile: Bool = false, sourceURL: URL? = nil, kind: ShelfItemKind = .file, title: String? = nil) {
        self.id = id
        self.url = Self.canonical(url)
        self.addedAt = addedAt
        self.isReachable = Self.checkReachable(self.url)
        self.ownsFile = ownsFile
        self.sourceURL = sourceURL.map(Self.canonical)
        self.kind = kind
        self.title = title
        self.bookmark = try? url.bookmarkData(options: .minimalBookmark)
    }

    var name: String { url.lastPathComponent }

    var label: String {
        switch kind {
        case .text, .link: title ?? name
        case .file, .image: name
        }
    }

    static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func checkReachable(_ url: URL) -> Bool {
        (try? url.checkResourceIsReachable()) == true
    }

    private enum CodingKeys: String, CodingKey {
        case id, url, addedAt, isReachable, bookmark, ownsFile, sourceURL, kind, title
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(URL.self, forKey: .url)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        isReachable = try container.decode(Bool.self, forKey: .isReachable)
        bookmark = try container.decodeIfPresent(Data.self, forKey: .bookmark)
        ownsFile = try container.decodeIfPresent(Bool.self, forKey: .ownsFile) ?? false
        sourceURL = try container.decodeIfPresent(URL.self, forKey: .sourceURL)
        kind = try container.decodeIfPresent(ShelfItemKind.self, forKey: .kind) ?? .file
        title = try container.decodeIfPresent(String.self, forKey: .title)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(addedAt, forKey: .addedAt)
        try container.encode(isReachable, forKey: .isReachable)
        try container.encode(bookmark, forKey: .bookmark)
        try container.encode(ownsFile, forKey: .ownsFile)
        try container.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(title, forKey: .title)
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
