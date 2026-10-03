import Foundation

enum ShelfCopyMode: String, CaseIterable, Identifiable, Sendable {
    case never
    case temporary
    case always

    init(stored: String?) {
        self = stored.flatMap(Self.init(rawValue:)) ?? .temporary
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .never: "Never"
        case .temporary: "Only from temporary locations"
        case .always: "Always"
        }
    }
}

enum ShelfFileLocation {
    static func isTemporary(_ url: URL, homeDirectory: URL, temporaryDirectory: URL) -> Bool {
        let path = ShelfItem.canonical(url).path
        let home = ShelfItem.canonical(homeDirectory)
        let prefixes = [
            ShelfItem.canonical(temporaryDirectory).path,
            "/private/tmp",
            "/private/var/folders",
            home.appending(path: "Library").appending(path: "Containers").path,
            home.appending(path: "Library").appending(path: "Group Containers").path,
        ]
        return prefixes.contains { isInside(path, directory: $0) }
    }

    private static func isInside(_ path: String, directory: String) -> Bool {
        let root = directory.hasSuffix("/") ? String(directory.dropLast()) : directory
        guard !root.isEmpty, root != "/" else { return false }
        return path == root || path.hasPrefix(root + "/")
    }
}
