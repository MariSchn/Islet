import Foundation
import Testing
@testable import DownloadsPlugin

final class FolderListingTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "FolderListingTests." + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    @Test func listsUnfinishedDownloadsWithTheirSizeAndOtherFilesByName() throws {
        try Data(count: 1000).write(to: folder.appending(path: "movie.mp4.crdownload"))
        try Data(count: 10).write(to: folder.appending(path: "notes.txt"))
        try Data(count: 10).write(to: folder.appending(path: ".DS_Store"))
        let bundle = folder.appending(path: "report.pdf.download")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data(count: 500).write(to: bundle.appending(path: "report.pdf"))
        try Data(count: 20).write(to: bundle.appending(path: "Info.plist"))

        let listing = try FolderListing.read(folder, finalNames: ["notes.txt", "missing.zip"])

        #expect(Set(listing.unfinished.keys) == ["movie.mp4", "report.pdf"])
        #expect(listing.unfinished["movie.mp4"]?.bytes == 1000)
        #expect(listing.unfinished["report.pdf"]?.bytes == 520)
        #expect(Set(listing.finalFiles.keys) == ["notes.txt"])
        #expect(listing.finalFiles["notes.txt"]?.bytes == 10)
    }

    @Test func recognizesDeniedAccess() {
        let denied = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM)),
        ])
        #expect(FolderListing.isAccessDenied(denied))
        #expect(FolderListing.isAccessDenied(NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))))
        #expect(!FolderListing.isAccessDenied(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)))
    }
}
