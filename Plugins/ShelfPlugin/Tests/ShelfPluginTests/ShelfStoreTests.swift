import Foundation
import Testing
@testable import ShelfPlugin

@MainActor
struct ShelfStoreTests {
    let directory: URL
    let fileA: URL
    let fileB: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ShelfStoreTests." + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileA = directory.appending(path: "a.txt")
        fileB = directory.appending(path: "b.txt")
        try Data("a".utf8).write(to: fileA)
        try Data("b".utf8).write(to: fileB)
    }

    @Test func addsNewestFirstAndIgnoresDuplicatesAndNonFileURLs() {
        let store = ShelfStore(directory: directory)

        store.add([fileA])
        let added = store.add([fileB, fileA, fileB, URL(string: "https://example.com")!])

        #expect(added.map(\.url) == [fileB])
        #expect(store.items.map(\.url) == [fileB, fileA])
    }

    @Test func removeAndRemoveAll() {
        let store = ShelfStore(directory: directory)
        store.add([fileA, fileB])

        store.remove(store.items[0].id)
        #expect(store.items.map(\.url) == [fileB])

        store.removeAll()
        #expect(store.items.isEmpty)
    }

    @Test func persistsAcrossInstances() {
        let first = ShelfStore(directory: directory)
        first.add([fileA, fileB])

        let second = ShelfStore(directory: directory)
        second.load()

        #expect(second.items == first.items)
    }

    @Test func followsRenamedFilesThroughBookmarks() throws {
        let first = ShelfStore(directory: directory)
        first.add([fileA])
        let moved = directory.appending(path: "renamed.txt")
        try FileManager.default.moveItem(at: fileA, to: moved)

        let second = ShelfStore(directory: directory)
        second.load()

        #expect(second.items.first?.url == moved.standardizedFileURL)
        #expect(second.items.first?.isReachable == true)
    }

    @Test func loadWithoutFileKeepsEmptyShelf() {
        let store = ShelfStore(directory: directory)
        store.load()
        #expect(store.items.isEmpty)
    }
}
