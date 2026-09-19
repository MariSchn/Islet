import Foundation
import Testing
@testable import ShelfPlugin

@MainActor
final class ShelfStoreTests {
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

    isolated deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func canonical(_ url: URL) -> URL { ShelfItem.canonical(url) }

    @Test func addsNewestFirstAndIgnoresDuplicatesAndNonFileURLs() {
        let store = ShelfStore(directory: directory)

        store.add([fileA])
        let added = store.add([fileB, fileA, fileB, URL(string: "https://example.com")!])

        #expect(added.map(\.url) == [canonical(fileB)])
        #expect(store.items.map(\.url) == [canonical(fileB), canonical(fileA)])
    }

    @Test func dedupesSymlinkedPaths() throws {
        let link = directory.appending(path: "link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fileA)
        let store = ShelfStore(directory: directory)

        store.add([fileA])
        let added = store.add([link])

        #expect(added.isEmpty)
        #expect(store.items.count == 1)
    }

    @Test func removeAndRemoveAll() {
        let store = ShelfStore(directory: directory)
        store.add([fileA, fileB])

        store.remove(store.items[0].id)
        #expect(store.items.map(\.url) == [canonical(fileB)])

        store.removeAll()
        #expect(store.items.isEmpty)
    }

    @Test func persistsAcrossInstances() {
        let first = ShelfStore(directory: directory)
        first.add([fileA, fileB])

        let second = ShelfStore(directory: directory)
        second.load()

        #expect(second.items.map(\.id) == first.items.map(\.id))
        #expect(second.items.map(\.url) == first.items.map(\.url))
    }

    @Test func followsRenamedFilesThroughBookmarksAndSavesResolvedURL() throws {
        let first = ShelfStore(directory: directory)
        first.add([fileA])
        let moved = directory.appending(path: "renamed.txt")
        try FileManager.default.moveItem(at: fileA, to: moved)

        let second = ShelfStore(directory: directory)
        second.load()
        #expect(second.items.first?.url == canonical(moved))

        let data = try Data(contentsOf: directory.appending(path: "shelf.json"))
        #expect(String(decoding: data, as: UTF8.self).contains("renamed.txt"))
    }

    @Test func deletedFileKeepsItsEntryAndBecomesUnreachable() async throws {
        let first = ShelfStore(directory: directory)
        first.add([fileA])
        #expect(first.items[0].isReachable)
        try FileManager.default.removeItem(at: fileA)

        let second = ShelfStore(directory: directory)
        second.load()
        for _ in 0..<50 where second.items.first?.isReachable == true {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(second.items.first?.url == canonical(fileA))
        #expect(second.items.first?.isReachable == false)
    }

    @Test func corruptFileIsSetAsideInsteadOfOverwritten() throws {
        let shelfFile = directory.appending(path: "shelf.json")
        try Data("not json".utf8).write(to: shelfFile)

        let store = ShelfStore(directory: directory)
        store.load()

        #expect(store.items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: shelfFile.appendingPathExtension("corrupt").path))
        #expect(!FileManager.default.fileExists(atPath: shelfFile.path))
    }

    @Test func loadWithoutFileKeepsEmptyShelf() {
        let store = ShelfStore(directory: directory)
        store.load()
        #expect(store.items.isEmpty)
    }
}
