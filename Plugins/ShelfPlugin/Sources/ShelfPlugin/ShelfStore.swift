import Foundation
import Observation
import os

@MainActor
@Observable
public final class ShelfStore {
    public private(set) var items: [ShelfItem] = []

    private let fileURL: URL
    private let logger: Logger

    public init(directory: URL, logger: Logger = Logger()) {
        fileURL = directory.appending(path: "shelf.json")
        self.logger = logger
    }

    public func load() {
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
    public func add(_ urls: [URL]) -> [ShelfItem] {
        let existing = Set(items.map(\.url))
        var seen = Set<URL>()
        let added = urls
            .filter(\.isFileURL)
            .map(ShelfItem.canonical)
            .filter { !existing.contains($0) && seen.insert($0).inserted }
            .map { ShelfItem(url: $0) }
        guard !added.isEmpty else { return [] }
        items.insert(contentsOf: added, at: 0)
        save()
        return added
    }

    public func remove(_ id: ShelfItem.ID) {
        guard items.contains(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        save()
    }

    public func refreshReachability() {
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

    public func removeAll() {
        items.removeAll()
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
