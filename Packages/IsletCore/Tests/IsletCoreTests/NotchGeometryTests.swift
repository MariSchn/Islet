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
        #expect(geometry.panelSize == CGSize(width: 1080, height: 583))
        #expect(geometry.panelFrame.contains(geometry.expandedShapeFrame(for: geometry.largestScreenSize)))
    }

    @Test func screenSizeIsClampedBetweenMinimumAndScreenBounds() {
        let geometry = NotchGeometry(screenFrame: screen, notchSize: CGSize(width: 196, height: 32), hasHardwareNotch: true)

        #expect(geometry.screenSize(for: nil) == NotchGeometry.defaultScreenSize)
        #expect(geometry.screenSize(for: CGSize(width: 10, height: 10)) == NotchGeometry.minScreenSize)
        #expect(geometry.screenSize(for: CGSize(width: 5000, height: 5000)) == CGSize(width: 960, height: 491))
        #expect(geometry.expandedShapeSize(for: CGSize(width: 400, height: 100)) == CGSize(width: 400, height: 132))
        #expect(geometry.expandedShapeFrame(for: CGSize(width: 400, height: 100)).midX == screen.midX)
    }

    @Test func largestScreenSizeIsUnboundedWithoutScreen() {
        #expect(NotchGeometry.placeholder.largestScreenSize == NotchGeometry.maxScreenSize)
    }

    @Test func pillShapeFitsTextAndKeepsNotchInPlace() {
        let geometry = NotchGeometry(screenFrame: screen, notchSize: CGSize(width: 196, height: 32), hasHardwareNotch: true)
        let short = PillStatus(text: "Hi")
        let long = PillStatus(text: String(repeating: "Playing a very long track title ", count: 4))
        let leading = NotchGeometry.pillLeadingWidth

        let shortTrailing = geometry.pillTrailingWidth(for: short.text)
        #expect(shortTrailing > 2 * NotchGeometry.pillTextPadding)
        #expect(shortTrailing < 60)
        #expect(geometry.pillTrailingWidth(for: long.text) == NotchGeometry.pillTrailingMaxWidth)

        for pill in [short, long] {
            let size = geometry.pillShapeSize(for: pill)
            let offset = geometry.pillShapeOffset(for: pill)
            #expect(size.height == 32)
            #expect(size.width + 2 * abs(offset) <= geometry.panelSize.width)
            let shapeMinX = geometry.panelFrame.midX - size.width / 2 + offset
            #expect(shapeMinX + leading == screen.midX - 196 / 2)
        }
    }

    @Test func pillStaysInsidePanelForVeryWideNotch() {
        let geometry = NotchGeometry(screenFrame: screen, notchSize: CGSize(width: 800, height: 32), hasHardwareNotch: true)
        let pill = PillStatus(text: String(repeating: "wide ", count: 20))

        let size = geometry.pillShapeSize(for: pill)
        let offset = geometry.pillShapeOffset(for: pill)

        #expect(size.width + 2 * abs(offset) <= geometry.panelSize.width)
        #expect(geometry.pillTrailingWidth(for: pill.text) < NotchGeometry.pillTrailingMaxWidth)
    }

    @Test func expandedShapeFrameIsCenteredAtTopInScreenCoordinates() {
        let external = CGRect(x: 1512, y: 200, width: 2560, height: 1440)
        let geometry = NotchGeometry(screenFrame: external, notchSize: CGSize(width: 200, height: 24), hasHardwareNotch: false)

        #expect(geometry.expandedShapeFrame.midX == external.midX)
        #expect(geometry.expandedShapeFrame.maxY == external.maxY)
        #expect(geometry.expandedShapeFrame.size == geometry.expandedShapeSize)
        #expect(geometry.panelFrame.contains(geometry.expandedShapeFrame))
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

    @Test func artworkPillUsesSymmetricSlots() {
        let geometry = NotchGeometry.placeholder
        let artwork = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        let pill = PillStatus(text: String(repeating: "wide ", count: 20), artwork: artwork)

        #expect(geometry.pillTrailingWidth(for: pill) == NotchGeometry.pillLeadingWidth)
        #expect(geometry.pillShapeOffset(for: pill) == 0)
        #expect(geometry.pillShapeSize(for: pill).width == geometry.notchSize.width + 2 * NotchGeometry.pillLeadingWidth)
    }
}
