import AppKit

public struct NotchGeometry: Sendable, Equatable {
    public static let fallbackNotchSize = CGSize(width: 200, height: 32)
    public static let expandedSize = CGSize(width: 520, height: 220)
    public static let overshootMargin: CGFloat = 60

    public let screenFrame: CGRect
    public let notchSize: CGSize
    public let hasHardwareNotch: Bool

    public init(screenFrame: CGRect, notchSize: CGSize, hasHardwareNotch: Bool) {
        self.screenFrame = screenFrame
        self.notchSize = notchSize
        self.hasHardwareNotch = hasHardwareNotch
    }

    public init(screen: NSScreen) {
        let frame = screen.frame
        let insetTop = screen.safeAreaInsets.top
        if insetTop > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            self.init(
                screenFrame: frame,
                notchSize: CGSize(width: right.minX - left.maxX, height: insetTop),
                hasHardwareNotch: true
            )
        } else {
            self.init(screenFrame: frame, notchSize: Self.fallbackNotchSize, hasHardwareNotch: false)
        }
    }

    public var expandedShapeSize: CGSize {
        CGSize(
            width: max(Self.expandedSize.width, notchSize.width),
            height: notchSize.height + Self.expandedSize.height
        )
    }

    public var panelSize: CGSize {
        CGSize(
            width: expandedShapeSize.width + 2 * Self.overshootMargin,
            height: expandedShapeSize.height + Self.overshootMargin
        )
    }

    public var panelFrame: CGRect {
        CGRect(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.maxY - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    public static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }
}
