import CoreGraphics
import Testing
@testable import DownloadsPlugin

@MainActor
struct DownloadsSizingTests {
    let padding: CGFloat = 2 * 12
    let active: CGFloat = 40
    let recent: CGFloat = 32
    let spacing: CGFloat = 4
    let sectionSpacing: CGFloat = 12

    private func height(active: Int, recent: Int) -> CGFloat {
        DownloadsPlugin.contentSize(activeCount: active, recentCount: recent, accessDenied: false).height
    }

    @Test func emptyAndDeniedStatesHaveFixedHeights() {
        #expect(DownloadsPlugin.contentSize(activeCount: 0, recentCount: 0, accessDenied: false) == CGSize(width: 380, height: padding + 72))
        #expect(DownloadsPlugin.contentSize(activeCount: 2, recentCount: 5, accessDenied: true) == CGSize(width: 380, height: padding + 96))
    }

    @Test func heightGrowsWithRows() {
        #expect(height(active: 1, recent: 0) == padding + active)
        #expect(height(active: 2, recent: 0) == padding + 2 * active + spacing)
        #expect(height(active: 0, recent: 3) == padding + 3 * recent + 2 * spacing)
        let mixed = active + sectionSpacing + 2 * recent + spacing
        #expect(height(active: 1, recent: 2) == padding + mixed)
    }

    @Test func heightStopsGrowingAtTheMaximum() {
        #expect(height(active: 0, recent: 8) == padding + 8 * recent + 7 * spacing)
        #expect(height(active: 3, recent: 8) == padding + 320)
    }
}
