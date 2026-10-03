import Foundation
import Testing
@testable import ShelfPlugin

struct ShelfCopyTests {
    private let home = URL(fileURLWithPath: "/Users/tester")
    private let temporary = URL(fileURLWithPath: "/Volumes/IsletShelfTemp")

    private func isTemporary(_ url: URL) -> Bool {
        ShelfFileLocation.isTemporary(url, homeDirectory: home, temporaryDirectory: temporary)
    }

    @Test func temporaryLocationsAreRecognized() {
        #expect(isTemporary(temporary.appending(path: "shot.png")))
        #expect(isTemporary(URL(fileURLWithPath: "/private/tmp/shot.png")))
        #expect(isTemporary(URL(fileURLWithPath: "/private/var/folders/ab/shot.png")))
        #expect(isTemporary(home.appending(path: "Library/Containers/com.apple.mail/Data/shot.png")))
        #expect(isTemporary(home.appending(path: "Library/Group Containers/group.com.example/shot.png")))
    }

    @Test func documentsAreNotTemporary() {
        #expect(!isTemporary(home.appending(path: "Documents/notes.txt")))
    }

    @Test func prefixMatchesRequireADirectoryBoundary() {
        #expect(!isTemporary(URL(fileURLWithPath: "/private/tmp-extra/shot.png")))
        #expect(!isTemporary(URL(fileURLWithPath: "/private/var/folders-extra/shot.png")))
        #expect(!isTemporary(home.appending(path: "Library/Containers-extra/shot.png")))
    }

    @Test func canonicalTemporaryDirectoryMatchesTheResolvedFile() throws {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Caches/IsletShelfTests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appending(path: "target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let link = root.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let file = target.appending(path: "shot.png")

        #expect(ShelfFileLocation.isTemporary(file, homeDirectory: home, temporaryDirectory: link))
        #expect(!ShelfFileLocation.isTemporary(file, homeDirectory: home, temporaryDirectory: URL(fileURLWithPath: "/Volumes/somewhere-else")))
    }
}
