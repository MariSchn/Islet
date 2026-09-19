import CoreGraphics
import Testing
import IsletCore

struct NotchGeometryTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func panelIsCenteredAtTopOfScreenAndCoversExpandedSizePlusMargin() {
        let geometry = NotchGeometry(screenFrame: screen, notchSize: CGSize(width: 196, height: 32), hasHardwareNotch: true)

        #expect(geometry.panelFrame.midX == screen.midX)
        #expect(geometry.panelFrame.maxY == screen.maxY)
        #expect(geometry.expandedShapeSize == CGSize(width: 520, height: 252))
        #expect(geometry.panelSize == CGSize(width: 640, height: 312))
    }

    @Test func pillShapeWidensNotchOnBothSidesAtNotchHeight() {
        let geometry = NotchGeometry(screenFrame: screen, notchSize: CGSize(width: 196, height: 32), hasHardwareNotch: true)

        #expect(geometry.pillShapeSize == CGSize(width: 196 + 2 * NotchGeometry.pillSideWidth, height: 32))
        #expect(geometry.pillShapeSize.width <= geometry.panelSize.width)
    }

    @Test func expandedShapeNeverNarrowerThanNotch() {
        let geometry = NotchGeometry(screenFrame: screen, notchSize: CGSize(width: 800, height: 32), hasHardwareNotch: true)

        #expect(geometry.expandedShapeSize.width == 800)
    }

    @Test func secondaryScreenOffsetIsRespected() {
        let external = CGRect(x: 1512, y: 200, width: 2560, height: 1440)
        let geometry = NotchGeometry(screenFrame: external, notchSize: CGSize(width: 200, height: 24), hasHardwareNotch: false)

        #expect(geometry.panelFrame.midX == external.midX)
        #expect(geometry.panelFrame.maxY == external.maxY)
    }

    @Test func detectsHardwareNotchFromScreenMetrics() {
        let geometry = NotchGeometry(
            screenFrame: screen,
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
            safeAreaTop: 38,
            auxiliaryTopLeftArea: CGRect(x: 0, y: 944, width: 658, height: 38),
            auxiliaryTopRightArea: CGRect(x: 854, y: 944, width: 658, height: 38)
        )

        #expect(geometry.hasHardwareNotch)
        #expect(geometry.notchSize == CGSize(width: 196, height: 38))
    }

    @Test func fallsBackToMenuBarHeightWithoutNotch() {
        let external = CGRect(x: 0, y: 0, width: 3440, height: 1440)
        let geometry = NotchGeometry(
            screenFrame: external,
            visibleFrame: CGRect(x: 0, y: 80, width: 3440, height: 1335),
            safeAreaTop: 0,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        )

        #expect(!geometry.hasHardwareNotch)
        #expect(geometry.notchSize == CGSize(width: NotchGeometry.fallbackNotchWidth, height: 25))
    }

    @Test func fallsBackToDefaultHeightWhenMenuBarIsHidden() {
        let geometry = NotchGeometry(
            screenFrame: screen,
            visibleFrame: screen,
            safeAreaTop: 0,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        )

        #expect(geometry.notchSize.height == NotchGeometry.fallbackMenuBarHeight)
    }
}
