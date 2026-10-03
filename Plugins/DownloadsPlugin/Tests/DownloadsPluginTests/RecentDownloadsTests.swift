import Foundation
import Testing
@testable import DownloadsPlugin

@MainActor
final class RecentDownloadsTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "RecentDownloadsTests." + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    isolated deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func file(_ name: String, bytes: Int = 4) throws -> URL {
        let url = directory.appending(path: name)
        try Data(count: bytes).write(to: url)
        return RecentDownload.canonical(url)
    }

    @Test func keepsTheLatestEightNewestFirst() throws {
        let store = RecentDownloads(directory: directory)
        let files = try (0..<10).map { try file("\($0).bin") }

        for file in files {
            store.add(file)
        }

        #expect(store.items.map(\.url) == files.reversed().prefix(8).map(\.self))
    }

    @Test func addingAFileAgainMovesItToTheTop() throws {
        let store = RecentDownloads(directory: directory)
        let a = try file("a.zip", bytes: 12)
        let b = try file("b.zip")

        store.add(a)
        store.add(b)
        store.add(a)

        #expect(store.items.map(\.url) == [a, b])
        #expect(store.items.first?.bytes == 12)
    }

    @Test func persistsAcrossInstances() throws {
        let first = RecentDownloads(directory: directory)
        first.add(try file("a.zip"))
        first.add(try file("b.zip"))

        let second = RecentDownloads(directory: directory)
        second.load()

        #expect(second.items.map(\.id) == first.items.map(\.id))
        #expect(second.items.map(\.url) == first.items.map(\.url))
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "recent.json").path))
    }

    @Test func dropsUnreachableFilesOnLoad() throws {
        let kept = try file("kept.zip")
        let deleted = try file("deleted.zip")
        let first = RecentDownloads(directory: directory)
        first.add(kept)
        first.add(deleted)
        try FileManager.default.removeItem(at: deleted)

        let second = RecentDownloads(directory: directory)
        second.load()
        #expect(second.items.map(\.url) == [kept])

        let third = RecentDownloads(directory: directory)
        third.load()
        #expect(third.items.map(\.url) == [kept])
    }

    @Test func followsRenamedFilesThroughBookmarks() throws {
        let original = try file("a.zip")
        let first = RecentDownloads(directory: directory)
        first.add(original)
        let moved = directory.appending(path: "renamed.zip")
        try FileManager.default.moveItem(at: original, to: moved)

        let second = RecentDownloads(directory: directory)
        second.load()

        #expect(second.items.map(\.url) == [RecentDownload.canonical(moved)])
    }

    @Test func refreshFillsInTheSizeOfAFileThatAppearedLater() async throws {
        let store = RecentDownloads(directory: directory)
        let url = RecentDownload.canonical(directory.appending(path: "late.zip"))
        store.add(url)
        #expect(store.items.first?.bytes == nil)
        try Data(count: 64).write(to: url)

        store.refresh()
        let deadline = ContinuousClock.now + .seconds(5)
        while store.items.first?.bytes != 64 {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func refreshDropsDeletedFiles() async throws {
        let store = RecentDownloads(directory: directory)
        let kept = try file("kept.zip")
        let deleted = try file("deleted.zip")
        store.add(kept)
        store.add(deleted)
        try FileManager.default.removeItem(at: deleted)

        store.refresh()
        let deadline = ContinuousClock.now + .seconds(5)
        while store.items.map(\.url) != [kept] {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func removesAnItem() throws {
        let store = RecentDownloads(directory: directory)
        store.add(try file("a.zip"))
        store.add(try file("b.zip"))

        store.remove(store.items[0].id)

        #expect(store.items.map(\.name) == ["a.zip"])
    }

    @Test func corruptFileIsSetAside() throws {
        let recentFile = directory.appending(path: "recent.json")
        try Data("not json".utf8).write(to: recentFile)

        let store = RecentDownloads(directory: directory)
        store.load()

        #expect(store.items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: recentFile.appendingPathExtension("corrupt").path))
    }
}
