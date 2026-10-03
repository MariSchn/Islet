import Foundation
import Observation
import os

@MainActor
@Observable
final class ShelfStore {
    private(set) var items: [ShelfItem] = []
    var copyMode: ShelfCopyMode = .never
    var showsCountPill = false

    private let directory: URL
    private let fileURL: URL
    private let logger: Logger
    private let homeDirectory: URL
    private let temporaryDirectory: URL
    @ObservationIgnored private var copying: Set<URL> = []

    init(
        directory: URL,
        logger: Logger = Logger(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        temporaryDirectory: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    ) {
        self.directory = directory
        fileURL = directory.appending(path: "shelf.json")
        self.logger = logger
        self.homeDirectory = homeDirectory
        self.temporaryDirectory = temporaryDirectory
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        var loaded: [ShelfItem]
        do {
            loaded = try JSONDecoder().decode([ShelfItem].self, from: data)
        } catch {
            logger.error("Could not read \(self.fileURL.path, privacy: .public), keeping it aside: \(error, privacy: .public)")
            try? FileManager.default.moveItem(at: fileURL, to: fileURL.appendingPathExtension("corrupt"))
            return
        }
        var changed = false
        for index in loaded.indices {
            changed = loaded[index].resolveBookmark() || changed
        }
        items = loaded
        if changed {
            save()
        }
        refreshReachability()
    }

    @discardableResult
    func add(_ urls: [URL]) async -> [ShelfItem] {
        let existing = Set(items.map(\.url)).union(items.compactMap(\.sourceURL)).union(copying)
        var seen = Set<URL>()
        let sources = urls
            .filter(\.isFileURL)
            .map(ShelfItem.canonical)
            .filter { !existing.contains($0) && seen.insert($0).inserted }
        guard !sources.isEmpty else { return [] }

        let pending = sources.map { source in
            let id = UUID()
            return PendingAdd(
                id: id,
                source: source,
                folder: shouldCopy(source) ? ownedFolder(for: id) : nil
            )
        }
        let reserved = Set(pending.compactMap { $0.folder == nil ? nil : $0.source })
        copying.formUnion(reserved)
        defer { copying.subtract(reserved) }

        let logger = logger
        let copied: [URL?]
        if pending.contains(where: { $0.folder != nil }) {
            copied = await Task.detached {
                pending.map { item in
                    guard let folder = item.folder else { return nil }
                    return Self.copyItem(from: item.source, to: folder, logger: logger)
                }
            }.value
        } else {
            copied = Array(repeating: nil, count: pending.count)
        }

        let added = zip(pending, copied).map { item, copy in
            if let copy {
                ShelfItem(id: item.id, url: copy, ownsFile: true, sourceURL: item.source)
            } else {
                ShelfItem(url: item.source)
            }
        }
        guard !added.isEmpty else { return [] }
        items.insert(contentsOf: added, at: 0)
        save()
        return added
    }

    func remove(_ id: ShelfItem.ID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        save()
        deleteOwnedCopy(of: item)
    }

    func refreshReachability() {
        let snapshot = items.map { ($0.id, $0.url) }
        Task.detached(priority: .utility) { [weak self] in
            let results = snapshot.map { ($0.0, ShelfItem.checkReachable($0.1)) }
            await self?.apply(reachability: results)
        }
    }

    private func apply(reachability: [(ShelfItem.ID, Bool)]) {
        let lookup = Dictionary(reachability, uniquingKeysWith: { first, _ in first })
        for index in items.indices {
            if let reachable = lookup[items[index].id], items[index].isReachable != reachable {
                items[index].isReachable = reachable
            }
        }
    }

    func removeAll() {
        let owned = items.filter(\.ownsFile)
        items.removeAll()
        save()
        for item in owned {
            deleteOwnedCopy(of: item)
        }
    }

    private func shouldCopy(_ url: URL) -> Bool {
        switch copyMode {
        case .never:
            false
        case .always:
            true
        case .temporary:
            ShelfFileLocation.isTemporary(url, homeDirectory: homeDirectory, temporaryDirectory: temporaryDirectory)
        }
    }

    private func ownedFolder(for id: UUID) -> URL {
        directory.appending(path: "Items").appending(path: id.uuidString)
    }

    private func deleteOwnedCopy(of item: ShelfItem) {
        guard item.ownsFile else { return }
        let folder = ownedFolder(for: item.id)
        do {
            try FileManager.default.removeItem(at: folder)
        } catch {
            logger.error("Failed to delete \(folder.path, privacy: .public): \(error, privacy: .public)")
        }
    }

    private nonisolated static func copyItem(from source: URL, to folder: URL, logger: Logger) -> URL? {
        let destination = folder.appending(path: source.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            logger.error("Failed to copy \(source.path, privacy: .public): \(error, privacy: .public)")
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
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

private struct PendingAdd: Sendable {
    let id: UUID
    let source: URL
    let folder: URL?
}
