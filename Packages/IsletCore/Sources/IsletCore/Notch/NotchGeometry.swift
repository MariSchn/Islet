import AppKit

public struct NotchGeometry: Sendable, Equatable {
    public static let fallbackNotchWidth: CGFloat = 200
    public static let fallbackMenuBarHeight: CGFloat = 24
    public static let defaultScreenSize = CGSize(width: 520, height: 220)
    public static let minScreenSize = CGSize(width: 240, height: 80)
    public static let maxScreenSize = CGSize(width: 960, height: 640)
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

    public var largestScreenSize: CGSize {
        guard screenFrame.width > 0 else { return Self.maxScreenSize }
        return CGSize(
            width: min(Self.maxScreenSize.width, screenFrame.width - 2 * Self.overshootMargin),
            height: min(Self.maxScreenSize.height, screenFrame.height / 2)
        )
    }

    public func screenSize(for requested: CGSize?) -> CGSize {
        let requested = requested ?? Self.defaultScreenSize
        let largest = largestScreenSize
        return CGSize(
            width: min(max(requested.width, Self.minScreenSize.width), largest.width),
            height: min(max(requested.height, Self.minScreenSize.height), largest.height)
        )
    }

    public func expandedShapeSize(for screenSize: CGSize? = nil) -> CGSize {
        let screen = self.screenSize(for: screenSize)
        return CGSize(
            width: max(screen.width, notchSize.width),
            height: notchSize.height + screen.height
        )
    }

    public var expandedShapeSize: CGSize {
        expandedShapeSize(for: nil)
    }

    public var largestExpandedShapeSize: CGSize {
        expandedShapeSize(for: largestScreenSize)
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

    public func expandedShapeFrame(for screenSize: CGSize? = nil) -> CGRect {
        let size = expandedShapeSize(for: screenSize)
        return CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    public var expandedShapeFrame: CGRect {
        expandedShapeFrame(for: nil)
    }

    public var panelSize: CGSize {
        CGSize(
            width: largestExpandedShapeSize.width + 2 * Self.overshootMargin,
            height: largestExpandedShapeSize.height + Self.overshootMargin
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
