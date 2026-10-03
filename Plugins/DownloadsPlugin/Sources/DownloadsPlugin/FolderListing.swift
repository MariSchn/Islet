import Foundation

enum DownloadName {
    static let unfinishedExtensions: Set<String> = ["download", "crdownload", "part"]

    static func finalName(forUnfinished fileName: String) -> String? {
        let url = URL(filePath: fileName, directoryHint: .notDirectory)
        guard unfinishedExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty || name == "." ? nil : name
    }
}

struct FolderListing: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        var bytes: Int64
        var modified: Date
    }

    var unfinished: [String: Entry] = [:]
    var finalFiles: [String: Entry] = [:]

    static func read(_ folder: URL, finalNames: Set<String> = []) throws -> FolderListing {
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        var listing = FolderListing()
        for name in names where !name.hasPrefix(".") {
            if let finalName = DownloadName.finalName(forUnfinished: name) {
                let entry = Self.entry(at: folder.appending(path: name))
                if let existing = listing.unfinished[finalName], existing.modified > entry.modified { continue }
                listing.unfinished[finalName] = entry
            } else if finalNames.contains(name) {
                listing.finalFiles[name] = Self.entry(at: folder.appending(path: name))
            }
        }
        return listing
    }

    static func isAccessDenied(_ error: any Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoPermissionError { return true }
        if error.domain == NSPOSIXErrorDomain, error.code == Int(EPERM) || error.code == Int(EACCES) { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isAccessDenied(underlying)
        }
        return false
    }

    private static let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]

    private static func entry(at url: URL) -> Entry {
        let values = try? url.resourceValues(forKeys: keys)
        var entry = Entry(bytes: Int64(values?.fileSize ?? 0), modified: values?.contentModificationDate ?? .distantPast)
        guard values?.isDirectory == true,
              let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        else { return entry }
        entry.bytes = 0
        for case let child as URL in enumerator {
            guard let values = try? child.resourceValues(forKeys: keys), values.isDirectory != true else { continue }
            entry.bytes += Int64(values.fileSize ?? 0)
            if let modified = values.contentModificationDate, modified > entry.modified {
                entry.modified = modified
            }
        }
        return entry
    }
}
