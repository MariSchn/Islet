import AppKit

public struct NotchGeometry: Sendable, Equatable {
    public static let fallbackNotchWidth: CGFloat = 200
    public static let fallbackMenuBarHeight: CGFloat = 24
    public static let expandedSize = CGSize(width: 520, height: 220)
    public static let overshootMargin: CGFloat = 60
    public static let pillLeadingWidth: CGFloat = 36
    public static let pillTrailingMaxWidth: CGFloat = 220
    public static let pillTextPadding: CGFloat = 10
    public static var pillFont: NSFont { .systemFont(ofSize: 12, weight: .medium) }

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

    public func pillTrailingWidth(for text: String) -> CGFloat {
        let textWidth = (text as NSString).size(withAttributes: [.font: Self.pillFont]).width
        let availableSideWidth = (panelSize.width - notchSize.width) / 2
        return min(ceil(textWidth) + 2 * Self.pillTextPadding, Self.pillTrailingMaxWidth, availableSideWidth)
    }

    public func pillTrailingWidth(for pill: PillStatus) -> CGFloat {
        pill.artwork == nil ? pillTrailingWidth(for: pill.text) : Self.pillLeadingWidth
    }

    public func pillShapeSize(for pill: PillStatus) -> CGSize {
        CGSize(
            width: notchSize.width + Self.pillLeadingWidth + pillTrailingWidth(for: pill),
            height: notchSize.height
        )
    }

    public func pillShapeOffset(for pill: PillStatus) -> CGFloat {
        (pillTrailingWidth(for: pill) - Self.pillLeadingWidth) / 2
    }

    public var expandedShapeFrame: CGRect {
        CGRect(
            x: screenFrame.midX - expandedShapeSize.width / 2,
            y: screenFrame.maxY - expandedShapeSize.height,
            width: expandedShapeSize.width,
            height: expandedShapeSize.height
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
