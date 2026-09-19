import CoreGraphics
import Testing
import IsletCore

struct NotchGeometryTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func panelIsCenteredAtTopOfScreenAndCoversExpandedSize() {
        let geometry = NotchGeometry(screenFrame: screen, notchSize: CGSize(width: 196, height: 32), hasHardwareNotch: true)

        #expect(geometry.panelFrame.midX == screen.midX)
        #expect(geometry.panelFrame.maxY == screen.maxY)
        #expect(geometry.expandedShapeSize == CGSize(width: 520, height: 252))
        #expect(geometry.panelSize == CGSize(width: 640, height: 312))
    }

    @Test func panelNeverNarrowerThanNotch() {
        let geometry = NotchGeometry(screenFrame: screen, notchSize: CGSize(width: 800, height: 32), hasHardwareNotch: true)

        #expect(geometry.expandedShapeSize.width == 800)
    }

    @Test func secondaryScreenOffsetIsRespected() {
        let external = CGRect(x: 1512, y: 200, width: 2560, height: 1440)
        let geometry = NotchGeometry(screenFrame: external, notchSize: NotchGeometry.fallbackNotchSize, hasHardwareNotch: false)

        #expect(geometry.panelFrame.midX == external.midX)
        #expect(geometry.panelFrame.maxY == external.maxY)
        #expect(!geometry.hasHardwareNotch)
    }
}
