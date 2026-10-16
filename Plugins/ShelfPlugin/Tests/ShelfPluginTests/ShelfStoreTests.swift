import Foundation
import IsletCore
import Testing
@testable import ShelfPlugin

@MainActor
final class ShelfStoreTests {
    let directory: URL
    let fileA: URL
    let fileB: URL
    private var plainRoots: [URL] = []

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
        for root in plainRoots {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func makePlainFile(named name: String = "note.txt") throws -> URL {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Caches/IsletShelfTests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        plainRoots.append(root)
        let file = root.appending(path: name)
        try Data("note".utf8).write(to: file)
        return file
    }

    private func canonical(_ url: URL) -> URL { ShelfItem.canonical(url) }

    @Test func addsNewestFirstAndIgnoresDuplicatesAndNonFileURLs() async {
        let store = ShelfStore(directory: directory)

        await store.add([fileA])
        let added = await store.add([fileB, fileA, fileB, URL(string: "https://example.com")!])

        #expect(added.map(\.url) == [canonical(fileB)])
        #expect(store.items.map(\.url) == [canonical(fileB), canonical(fileA)])
    }

    @Test func dedupesSymlinkedPaths() async throws {
        let link = directory.appending(path: "link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fileA)
        let store = ShelfStore(directory: directory)

        await store.add([fileA])
        let added = await store.add([link])

        #expect(added.isEmpty)
        #expect(store.items.count == 1)
    }

    @Test func removeAndRemoveAll() async {
        let store = ShelfStore(directory: directory)
        await store.add([fileA, fileB])

        store.remove(store.items[0].id)
        #expect(store.items.map(\.url) == [canonical(fileB)])

        store.removeAll()
        #expect(store.items.isEmpty)
    }

    @Test func persistsAcrossInstances() async {
        let first = ShelfStore(directory: directory)
        await first.add([fileA, fileB])

        let second = ShelfStore(directory: directory)
        second.load()

        #expect(second.items.map(\.id) == first.items.map(\.id))
        #expect(second.items.map(\.url) == first.items.map(\.url))
    }

    @Test func followsRenamedFilesThroughBookmarksAndSavesResolvedURL() async throws {
        let first = ShelfStore(directory: directory)
        await first.add([fileA])
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
        await first.add([fileA])
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

    @Test func loadingRemovesCopiesThatNoItemReferences() throws {
        let store = ShelfStore(directory: directory)
        let kept = try #require(store.addText("keep me"))
        let orphan = directory.appending(path: "Items").appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)

        ShelfStore(directory: directory).load()
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
        #expect(FileManager.default.fileExists(atPath: kept.url.path))

        try Data("not json".utf8).write(to: directory.appending(path: "shelf.json"))
        ShelfStore(directory: directory).load()
        #expect(FileManager.default.fileExists(atPath: kept.url.path))
    }

    @Test func loadWithoutFileKeepsEmptyShelf() {
        let store = ShelfStore(directory: directory)
        store.load()
        #expect(store.items.isEmpty)
    }

    @Test func copyModeNeverReferencesTemporaryFiles() async throws {
        let store = ShelfStore(directory: directory)
        store.copyMode = .never
        let added = await store.add([fileA])
        let item = try #require(added.first)
        #expect(item.ownsFile == false)
        #expect(item.url == canonical(fileA))
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "Items").path))
        store.remove(item.id)
        #expect(FileManager.default.fileExists(atPath: fileA.path))
    }

    @Test func copyModeTemporaryOwnsTemporaryFilesAndReferencesOthers() async throws {
        let plain = try makePlainFile()
        #expect(isTemporary(fileA))
        #expect(!isTemporary(plain))
        let store = ShelfStore(directory: directory)
        store.copyMode = .temporary

        let copied = try #require(await store.add([fileA]).first)
        #expect(copied.ownsFile)
        #expect(copied.url.lastPathComponent == fileA.lastPathComponent)
        #expect(copied.url.deletingLastPathComponent().lastPathComponent == copied.id.uuidString)
        #expect(try Data(contentsOf: copied.url) == Data("a".utf8))
        #expect(FileManager.default.fileExists(atPath: fileA.path))

        let referenced = try #require(await store.add([plain]).first)
        #expect(referenced.ownsFile == false)
        #expect(referenced.url == canonical(plain))
    }

    @Test func copyModeAlwaysOwnsFilesOutsideTemporaryLocations() async throws {
        let plain = try makePlainFile()
        let store = ShelfStore(directory: directory)
        store.copyMode = .always
        let added = try #require(await store.add([plain, plain]).first)
        #expect(store.items.count == 1)
        #expect(added.ownsFile)
        #expect(added.sourceURL == canonical(plain))
        #expect(try Data(contentsOf: added.url) == Data("note".utf8))
        #expect(FileManager.default.fileExists(atPath: plain.path))

        #expect(await store.add([plain]).isEmpty)
        let reloaded = ShelfStore(directory: directory)
        reloaded.copyMode = .always
        reloaded.load()
        #expect(await reloaded.add([plain]).isEmpty)
        #expect(reloaded.items.count == 1)
    }

    @Test func overlappingCopiesOfTheSameFileAddItOnce() async throws {
        let plain = try makePlainFile()
        let store = ShelfStore(directory: directory)
        store.copyMode = .always
        async let first = store.add([plain])
        async let second = store.add([plain])
        let (addedFirst, addedSecond) = await (first, second)
        #expect(addedFirst.count + addedSecond.count == 1)
        #expect(store.items.count == 1)
    }

    @Test func copiesFoldersRecursively() async throws {
        let folder = directory.appending(path: "Bundle")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("inner".utf8).write(to: folder.appending(path: "inside.txt"))
        let store = ShelfStore(directory: directory)
        store.copyMode = .always
        let added = try #require(await store.add([folder]).first)
        #expect(added.ownsFile)
        #expect(added.name == "Bundle")
        #expect(try Data(contentsOf: added.url.appending(path: "inside.txt")) == Data("inner".utf8))
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "inside.txt").path))
    }

    @Test func removingAnOwnedItemDeletesItsFolderAndKeepsTheOriginal() async throws {
        let store = ShelfStore(directory: directory)
        store.copyMode = .always
        let added = try #require(await store.add([fileA]).first)
        let folder = directory.appending(path: "Items").appending(path: added.id.uuidString)
        #expect(FileManager.default.fileExists(atPath: folder.path))

        let reloaded = ShelfStore(directory: directory)
        reloaded.load()
        #expect(reloaded.items.first?.ownsFile == true)
        #expect(reloaded.items.first?.id == added.id)
        reloaded.remove(added.id)

        #expect(reloaded.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(FileManager.default.fileExists(atPath: fileA.path))
    }

    @Test func clearingDeletesEveryOwnedFolder() async throws {
        let plain = try makePlainFile()
        let store = ShelfStore(directory: directory)
        store.copyMode = .always
        let owned = await store.add([fileA, fileB])
        store.copyMode = .never
        let referenced = try #require(await store.add([plain]).first)
        let folders = owned.map { directory.appending(path: "Items").appending(path: $0.id.uuidString) }

        store.removeAll()

        #expect(store.items.isEmpty)
        for folder in folders {
            #expect(!FileManager.default.fileExists(atPath: folder.path))
        }
        #expect(FileManager.default.fileExists(atPath: fileA.path))
        #expect(FileManager.default.fileExists(atPath: fileB.path))
        #expect(FileManager.default.fileExists(atPath: referenced.url.path))
    }

    @Test func failedCopyAddsTheOriginal() async throws {
        let missing = directory.appending(path: "missing.txt")
        let store = ShelfStore(directory: directory)
        store.copyMode = .always
        let added = try #require(await store.add([missing]).first)
        #expect(added.ownsFile == false)
        #expect(added.url == canonical(missing))
        let itemsRoot = directory.appending(path: "Items")
        if FileManager.default.fileExists(atPath: itemsRoot.path) {
            let contents = try FileManager.default.contentsOfDirectory(at: itemsRoot, includingPropertiesForKeys: nil)
            #expect(contents.isEmpty)
        }
    }

    @Test func loadsItemsSavedBeforeOwnsFileExisted() throws {
        struct LegacyItem: Encodable {
            let id: UUID
            let url: URL
            let addedAt: Date
            let isReachable: Bool
            let bookmark: Data?
        }
        let id = UUID()
        let legacy = [LegacyItem(id: id, url: canonical(fileA), addedAt: .now, isReachable: true, bookmark: nil)]
        try JSONEncoder().encode(legacy).write(to: directory.appending(path: "shelf.json"))

        let store = ShelfStore(directory: directory)
        store.load()

        #expect(store.items.count == 1)
        #expect(store.items[0].id == id)
        #expect(store.items[0].ownsFile == false)
        #expect(store.items[0].kind == .file)
        #expect(store.items[0].url == canonical(fileA))
    }

    @Test func addingTextCreatesAnOwnedTextFile() throws {
        let store = ShelfStore(directory: directory)
        let item = try #require(store.addText("  Hello world\nsecond line"))

        #expect(item.kind == .text)
        #expect(item.ownsFile)
        #expect(item.name == "Hello world.txt")
        #expect(item.label == "Hello world")
        #expect(try String(contentsOf: item.url, encoding: .utf8) == "  Hello world\nsecond line")
        #expect(store.items == [item])
    }

    @Test func addingALinkCreatesAWeblocFile() throws {
        let store = ShelfStore(directory: directory)
        let item = try #require(store.addLink(URL(string: "https://github.com/MariSchn/Islet?tab=readme")!))

        #expect(item.kind == .link)
        #expect(item.ownsFile)
        #expect(item.name == "github.com.webloc")
        #expect(item.label == "github.com")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: item.url), format: nil)
        #expect((plist as? [String: String]) == ["URL": "https://github.com/MariSchn/Islet?tab=readme"])
    }

    @Test func addingPNGDataCreatesAnOwnedImage() throws {
        let store = ShelfStore(directory: directory)
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let date = Date(timeIntervalSince1970: 0)
        let item = try #require(store.addImage(data: png, date: date))

        #expect(item.kind == .image)
        #expect(item.ownsFile)
        #expect(item.name == ShelfItemNaming.imageFileName(date: date))
        #expect(item.name.hasPrefix("Image "))
        #expect(item.name.hasSuffix(".png"))
        #expect(try Data(contentsOf: item.url) == png)
    }

    @Test func removingCreatedItemsDeletesTheirFolders() throws {
        let store = ShelfStore(directory: directory)
        let text = try #require(store.addText("hi"))
        let link = try #require(store.addLink(URL(string: "https://example.com")!))
        let image = try #require(store.addImage(data: Data([1])))
        let folders = [text, link, image].map { $0.url.deletingLastPathComponent() }
        for folder in folders {
            #expect(FileManager.default.fileExists(atPath: folder.path))
        }

        store.remove(text.id)
        store.remove(link.id)
        store.removeAll()

        for folder in folders {
            #expect(!FileManager.default.fileExists(atPath: folder.path))
        }
    }

    @Test func createdItemsPersistTheirKindAndTitle() throws {
        let store = ShelfStore(directory: directory)
        store.addText("Note\nbody")
        store.addLink(URL(string: "https://example.com/a")!)

        let reloaded = ShelfStore(directory: directory)
        reloaded.load()

        #expect(reloaded.items.map(\.kind) == [.link, .text])
        #expect(reloaded.items.map(\.label) == ["example.com", "Note"])
    }

    @Test func savesCopyModeWhenItChangesAndLeavesTheDefaultUnwritten() async throws {
        let suite = "ShelfStoreTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = PluginRegistry(storageRoot: root, userDefaults: defaults)
        let entry = try await registry.register(ShelfPlugin.self)
        let plugin = try #require(entry.plugin as? ShelfPlugin)
        let untouched: String? = entry.context.settings.value(forKey: ShelfPlugin.copyModeKey)
        #expect(plugin.store.copyMode == .temporary)
        #expect(untouched == nil)

        plugin.store.copyMode = .always
        let deadline = ContinuousClock.now + .seconds(2)
        var saved: String?
        while saved != ShelfCopyMode.always.rawValue {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
            saved = entry.context.settings.value(forKey: ShelfPlugin.copyModeKey)
        }
    }

    private func isTemporary(_ url: URL) -> Bool {
        ShelfFileLocation.isTemporary(
            url,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            temporaryDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        )
    }
}
