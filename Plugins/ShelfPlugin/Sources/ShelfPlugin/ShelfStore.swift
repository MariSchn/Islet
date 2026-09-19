import Foundation
import Observation

@MainActor
@Observable
public final class ShelfStore {
    public private(set) var items: [ShelfItem] = []

    private let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appending(path: "shelf.json")
    }

    public func load() {
        guard let data = try? Data(contentsOf: fileURL),
              var loaded = try? JSONDecoder().decode([ShelfItem].self, from: data) else { return }
        for index in loaded.indices {
            loaded[index].resolveBookmark()
        }
        items = loaded
    }

    @discardableResult
    public func add(_ urls: [URL]) -> [ShelfItem] {
        let existing = Set(items.map(\.url))
        var seen = Set<URL>()
        let added = urls
            .map(\.standardizedFileURL)
            .filter { $0.isFileURL && !existing.contains($0) && seen.insert($0).inserted }
            .map { ShelfItem(url: $0) }
        guard !added.isEmpty else { return [] }
        items.insert(contentsOf: added, at: 0)
        save()
        return added
    }

    public func remove(_ id: ShelfItem.ID) {
        items.removeAll { $0.id == id }
        save()
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
            NSLog("Shelf: failed to save: \(error)")
        }
    }
}
