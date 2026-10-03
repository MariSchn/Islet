import IsletCore
import Testing
@testable import DownloadsPlugin

@MainActor
struct DownloadsPillTests {
    @Test func noDownloadsShowNoPill() {
        #expect(DownloadsPlugin.pillStatus(for: []) == nil)
    }

    @Test func oneDownloadWithProgressShowsARingAndItsName() throws {
        let pill = try #require(DownloadsPlugin.pillStatus(for: [ActiveDownload(name: "report.pdf", fraction: 0.25, bytes: 1000)]))

        #expect(pill.text == "report.pdf")
        #expect(pill.priority == .ambient)
        #expect(pill.systemImage == "arrow.down.circle")
        #expect(pill.ring == PillStatus.Ring(segments: [
            .init(value: 0.25, tint: DownloadsPlugin.doneTint),
            .init(value: 0.75, tint: DownloadsPlugin.remainingTint),
        ]))
    }

    @Test func oneDownloadWithoutProgressShowsItsNameAndSize() throws {
        let pill = try #require(DownloadsPlugin.pillStatus(for: [ActiveDownload(name: "movie.mp4", bytes: 2_000_000)]))

        #expect(pill.text == "movie.mp4 · \(DownloadsPlugin.formatted(bytes: 2_000_000))")
        #expect(pill.ring == nil)
    }

    @Test func severalDownloadsShowTheirCountAndCombinedProgress() throws {
        let pill = try #require(DownloadsPlugin.pillStatus(for: [
            ActiveDownload(name: "a.zip", fraction: 0.2),
            ActiveDownload(name: "b.zip", fraction: 0.6),
        ]))

        #expect(pill.text == "2 downloads")
        #expect(pill.priority == .ambient)
        let done = try #require(pill.ring?.segments.first)
        #expect(abs(done.value - 0.4) < 0.0001)
        #expect(done.tint == DownloadsPlugin.doneTint)
    }

    @Test func severalDownloadsWithAnUnknownFractionShowNoRing() throws {
        let pill = try #require(DownloadsPlugin.pillStatus(for: [
            ActiveDownload(name: "a.zip", fraction: 0.2),
            ActiveDownload(name: "b.zip", bytes: 10),
            ActiveDownload(name: "c.zip"),
        ]))

        #expect(pill.text == "3 downloads")
        #expect(pill.ring == nil)
    }

    @Test func finishedDownloadsAreAnnounced() {
        #expect(DownloadsPlugin.announcement(for: FinishedDownload(names: ["report.pdf"])).text == "report.pdf downloaded")
        #expect(DownloadsPlugin.announcement(for: FinishedDownload(names: ["a.zip", "b.zip"])).text == "2 files downloaded")
    }
}
