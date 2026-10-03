import Foundation

struct ShelfSelection: Equatable, Sendable {
    private(set) var ids: Set<ShelfItem.ID> = []
    private(set) var anchor: ShelfItem.ID?

    func contains(_ id: ShelfItem.ID) -> Bool {
        ids.contains(id)
    }

    mutating func click(_ id: ShelfItem.ID) {
        ids = [id]
        anchor = id
    }

    mutating func commandClick(_ id: ShelfItem.ID) {
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        anchor = id
    }

    mutating func shiftClick(_ id: ShelfItem.ID, displayOrder: [ShelfItem.ID]) {
        guard
            let anchor,
            let start = displayOrder.firstIndex(of: anchor),
            let end = displayOrder.firstIndex(of: id)
        else {
            click(id)
            return
        }
        let range = displayOrder[min(start, end)...max(start, end)]
        ids = Set(range)
    }

    mutating func clear() {
        ids = []
        anchor = nil
    }

    mutating func remove(_ removed: some Sequence<ShelfItem.ID>) {
        let removed = Set(removed)
        ids.subtract(removed)
        if let anchor, removed.contains(anchor) {
            self.anchor = nil
        }
    }
}
