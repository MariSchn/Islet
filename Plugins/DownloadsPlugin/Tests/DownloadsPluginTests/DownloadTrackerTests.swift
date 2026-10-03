import Foundation
import Testing
@testable import DownloadsPlugin

struct DownloadTrackerTests {
    let now = Date()

    private func listing(unfinished: [String: Int64] = [:], finals: [String: Int64] = [:], modified: Date? = nil) -> FolderListing {
        FolderListing(
            unfinished: unfinished.mapValues { FolderListing.Entry(bytes: $0, modified: modified ?? now) },
            finalFiles: finals.mapValues { FolderListing.Entry(bytes: $0, modified: now) }
        )
    }

    @Test func finishesWhenTheUnfinishedFileDisappearsAndTheFinalFileAppears() {
        var tracker = DownloadTracker()

        #expect(tracker.apply(listing(unfinished: ["report.pdf": 10])) == [])
        #expect(tracker.downloads(now: now) == [ActiveDownload(name: "report.pdf", bytes: 10)])
        #expect(tracker.listedNames == ["report.pdf"])
        #expect(tracker.apply(listing(unfinished: ["report.pdf": 40])) == [])
        #expect(tracker.downloads(now: now) == [ActiveDownload(name: "report.pdf", bytes: 40)])
        #expect(tracker.apply(listing(finals: ["report.pdf": 40])) == ["report.pdf"])
        #expect(tracker.downloads(now: now).isEmpty)
        #expect(tracker.apply(listing()) == [])
    }

    @Test func cancelledDownloadsAndRenamesDoNotFinish() {
        var tracker = DownloadTracker()

        _ = tracker.apply(listing(unfinished: ["Unconfirmed 1": 5]))
        #expect(tracker.apply(listing(unfinished: ["movie.mp4": 5])) == [])
        #expect(tracker.downloads(now: now).map(\.name) == ["movie.mp4"])
        #expect(tracker.apply(listing()) == [])
        #expect(tracker.downloads(now: now).isEmpty)
    }

    @Test func emptyPlaceholdersAndOlderFilesDoNotCountAsFinished() {
        var tracker = DownloadTracker()

        _ = tracker.apply(listing(unfinished: ["setup.exe": 5]))
        #expect(tracker.apply(listing(finals: ["setup.exe": 0])) == [])

        let later = now.addingTimeInterval(DownloadTracker.finalFileTolerance + 1)
        _ = tracker.apply(listing(unfinished: ["notes.txt": 5], modified: later))
        #expect(tracker.apply(listing(finals: ["notes.txt": 5])) == [])
    }

    @Test func finishesSeveralDownloadsIndependently() {
        var tracker = DownloadTracker()

        _ = tracker.apply(listing(unfinished: ["a.zip": 1]))
        _ = tracker.apply(listing(unfinished: ["a.zip": 1, "b.zip": 1]))
        #expect(tracker.downloads(now: now).map(\.name) == ["a.zip", "b.zip"])
        #expect(tracker.apply(listing(unfinished: ["a.zip": 2], finals: ["b.zip": 1])) == ["b.zip"])
        #expect(tracker.apply(listing(finals: ["a.zip": 2, "b.zip": 1])) == ["a.zip"])
    }

    @Test func finishesOnceWhenProgressIsUnpublishedAtCompletion() {
        var tracker = DownloadTracker()
        let id = UUID()

        _ = tracker.apply(listing(unfinished: ["report.pdf": 10]))
        tracker.publish(id, PublishedProgress(name: "report.pdf", fraction: 0.25, bytes: nil, isComplete: false))
        #expect(tracker.downloads(now: now) == [ActiveDownload(name: "report.pdf", fraction: 0.25, bytes: 10)])
        tracker.update(id, PublishedProgress(name: "report.pdf", fraction: 1, bytes: nil, isComplete: true))
        #expect(tracker.unpublish(id, now: now) == "report.pdf")
        #expect(tracker.downloads(now: now).isEmpty)
        #expect(tracker.apply(listing(unfinished: ["report.pdf": 40])) == [])
        #expect(tracker.downloads(now: now).isEmpty)
        #expect(tracker.apply(listing(finals: ["report.pdf": 40])) == [])
    }

    @Test func progressFinishedBeforeTheFirstListingFinishesOnce() {
        var tracker = DownloadTracker()
        let id = UUID()

        tracker.publish(id, PublishedProgress(name: "small.zip", fraction: 0.5, bytes: nil, isComplete: false))
        tracker.update(id, PublishedProgress(name: "small.zip", fraction: 1, bytes: nil, isComplete: true))
        #expect(tracker.unpublish(id, now: now) == "small.zip")
        #expect(tracker.apply(listing(unfinished: ["small.zip": 8], modified: now.addingTimeInterval(-1))) == [])
        #expect(tracker.downloads(now: now).isEmpty)
        #expect(tracker.apply(listing(finals: ["small.zip": 8])) == [])
    }

    @Test func aNewDownloadWithTheSameNameIsTrackedAgain() {
        var tracker = DownloadTracker()

        _ = tracker.apply(listing(unfinished: ["a.zip": 1]), now: now)
        #expect(tracker.apply(listing(finals: ["a.zip": 1]), now: now) == ["a.zip"])
        let later = now.addingTimeInterval(30)
        _ = tracker.apply(listing(unfinished: ["a.zip": 1], modified: later), now: later)
        #expect(tracker.downloads(now: later).map(\.name) == ["a.zip"])
    }

    @Test func progressUnpublishedBeforeCompletionDoesNotFinish() {
        var tracker = DownloadTracker()
        let id = UUID()

        tracker.publish(id, PublishedProgress(name: "movie.mp4", fraction: 0.5, bytes: 100, isComplete: false))
        #expect(tracker.downloads(now: now) == [ActiveDownload(name: "movie.mp4", fraction: 0.5, bytes: 100)])
        #expect(tracker.unpublish(id) == nil)
        #expect(tracker.downloads(now: now).isEmpty)
    }

    @Test func listingAfterAFinishedProgressDoesNotFinishAgain() {
        var tracker = DownloadTracker()
        let id = UUID()

        _ = tracker.apply(listing(unfinished: ["a.dmg": 1]))
        tracker.publish(id, PublishedProgress(name: "a.dmg", fraction: 0.9, bytes: nil, isComplete: false))
        #expect(tracker.apply(listing(finals: ["a.dmg": 1])) == ["a.dmg"])
        tracker.update(id, PublishedProgress(name: "a.dmg", fraction: 1, bytes: nil, isComplete: true))
        #expect(tracker.unpublish(id) == nil)
    }

    @Test func hidesStaleUnfinishedFilesButStillDetectsTheirFinish() {
        var tracker = DownloadTracker()
        let old = now.addingTimeInterval(-DownloadTracker.staleAfter - 1)

        _ = tracker.apply(listing(unfinished: ["old.zip": 1], modified: old))
        #expect(tracker.downloads(now: now).isEmpty)
        #expect(tracker.hasListedDownloads)
        #expect(!tracker.hasRecentListedDownloads(now: now))
        #expect(tracker.apply(listing(finals: ["old.zip": 1])) == ["old.zip"])
    }
}
