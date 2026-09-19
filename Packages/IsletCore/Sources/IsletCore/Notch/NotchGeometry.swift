import AppKit

public struct NotchGeometry: Sendable, Equatable {
    public static let fallbackNotchWidth: CGFloat = 200
    public static let fallbackMenuBarHeight: CGFloat = 24
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

    public init(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeftArea: CGRect?,
        auxiliaryTopRightArea: CGRect?
    ) {
        if safeAreaTop > 0, let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea, right.minX > left.maxX {
            self.init(
                screenFrame: screenFrame,
                notchSize: CGSize(width: right.minX - left.maxX, height: safeAreaTop),
                hasHardwareNotch: true
            )
        } else {
            let menuBarHeight = screenFrame.maxY - visibleFrame.maxY
            self.init(
                screenFrame: screenFrame,
                notchSize: CGSize(
                    width: Self.fallbackNotchWidth,
                    height: menuBarHeight > 0 ? menuBarHeight : Self.fallbackMenuBarHeight
                ),
                hasHardwareNotch: false
            )
        }
    }

    public init(screen: NSScreen) {
        self.init(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea
        )
    }

    public static let placeholder = NotchGeometry(
        screenFrame: .zero,
        notchSize: CGSize(width: fallbackNotchWidth, height: fallbackMenuBarHeight),
        hasHardwareNotch: false
    )

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
