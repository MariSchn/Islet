import CoreGraphics
import Foundation
import Testing
@testable import ShelfPlugin

@MainActor
struct ShelfSizingTests {
    @Test func widthGrowsWithItemsBetweenBounds() {
        let height: CGFloat = 2 * 12 + 2 * 4 + 88
        #expect(ShelfPlugin.contentSize(forItemCount: 0) == CGSize(width: 360, height: height))
        #expect(ShelfPlugin.contentSize(forItemCount: 3) == CGSize(width: 360, height: height))
        #expect(ShelfPlugin.contentSize(forItemCount: 4) == CGSize(width: 2 * 12 + 2 * 4 + 4 * 84 + 3 * 8, height: height))
        #expect(ShelfPlugin.contentSize(forItemCount: 5) == CGSize(width: 2 * 12 + 2 * 4 + 5 * 84 + 4 * 8, height: height))
        #expect(ShelfPlugin.contentSize(forItemCount: 6) == CGSize(width: 520, height: height))
        #expect(ShelfPlugin.contentSize(forItemCount: 50) == CGSize(width: 520, height: height))
    }

    @Test func storeReportsItemChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ShelfSizingTests." + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "a.txt")
        try Data("a".utf8).write(to: file)
        let store = ShelfStore(directory: directory)
        var counts: [Int] = []
        store.onItemsChange = { counts.append(store.items.count) }

        store.add([file])
        store.removeAll()

        #expect(counts == [1, 0])
    }
}
