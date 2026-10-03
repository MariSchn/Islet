import Foundation

struct ActiveDownload: Identifiable, Equatable, Sendable {
    var name: String
    var fraction: Double?
    var bytes: Int64?

    var id: String { name }
}

struct PublishedProgress: Equatable, Sendable {
    var name: String
    var fraction: Double?
    var bytes: Int64?
    var isComplete: Bool
}

struct DownloadTracker {
    static let staleAfter: TimeInterval = 300
    static let finalFileTolerance: TimeInterval = 60

    private(set) var listed: [String: FolderListing.Entry] = [:]
    private var published: [UUID: PublishedProgress] = [:]
    private var completed: [String: Date] = [:]
    private var order: [String: Int] = [:]
    private var nextOrder = 0

    var hasListedDownloads: Bool { !listed.isEmpty }

    var listedNames: Set<String> { Set(listed.keys) }

    func hasRecentListedDownloads(now: Date) -> Bool {
        listed.contains { completed[$0.key] == nil && now.timeIntervalSince($0.value.modified) < Self.staleAfter }
    }

    mutating func apply(_ listing: FolderListing, now: Date = .now) -> [String] {
        var finished: [String] = []
        for (name, entry) in listed where listing.unfinished[name] == nil && completed[name] == nil {
            if let final = listing.finalFiles[name], final.bytes > 0,
               final.modified >= entry.modified.addingTimeInterval(-Self.finalFileTolerance) {
                finished.append(name)
                completed[name] = now
            }
        }
        for (name, entry) in listing.unfinished where listed[name] == nil {
            if let completedAt = completed[name], entry.modified > completedAt {
                completed[name] = nil
            }
            assignOrder(name)
        }
        listed = listing.unfinished
        pruneOrder()
        return finished.sorted()
    }

    mutating func publish(_ id: UUID, _ progress: PublishedProgress) {
        if !progress.isComplete {
            completed[progress.name] = nil
        }
        published[id] = progress
        assignOrder(progress.name)
    }

    mutating func update(_ id: UUID, _ progress: PublishedProgress) {
        guard published[id] != nil else { return }
        published[id] = progress
        assignOrder(progress.name)
        pruneOrder()
    }

    mutating func unpublish(_ id: UUID, now: Date = .now) -> String? {
        guard let progress = published.removeValue(forKey: id) else { return nil }
        pruneOrder()
        guard progress.isComplete, completed[progress.name] == nil else { return nil }
        completed[progress.name] = now
        return progress.name
    }

    func downloads(now: Date) -> [ActiveDownload] {
        var downloads: [String: ActiveDownload] = [:]
        for (name, entry) in listed where now.timeIntervalSince(entry.modified) < Self.staleAfter {
            downloads[name] = ActiveDownload(name: name, bytes: entry.bytes)
        }
        for progress in published.values {
            var download = downloads[progress.name] ?? ActiveDownload(name: progress.name, bytes: listed[progress.name]?.bytes)
            download.fraction = download.fraction ?? progress.fraction
            download.bytes = download.bytes ?? progress.bytes
            downloads[progress.name] = download
        }
        return downloads.values
            .filter { completed[$0.name] == nil }
            .sorted { (order[$0.name] ?? .max, $0.name) < (order[$1.name] ?? .max, $1.name) }
    }

    private mutating func assignOrder(_ name: String) {
        guard order[name] == nil else { return }
        order[name] = nextOrder
        nextOrder += 1
    }

    private mutating func pruneOrder() {
        let names = Set(listed.keys).union(published.values.map(\.name))
        order = order.filter { names.contains($0.key) }
    }
}
