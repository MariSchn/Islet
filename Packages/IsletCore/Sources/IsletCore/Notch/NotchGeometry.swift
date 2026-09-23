import AppKit

public struct NotchGeometry: Sendable, Equatable {
    public static let fallbackNotchWidth: CGFloat = 200
    public static let fallbackMenuBarHeight: CGFloat = 24
    public static let defaultContentSize = CGSize(width: 520, height: 220)
    public static let minContentSize = CGSize(width: 240, height: 80)
    public static let maxContentSize = CGSize(width: 960, height: 640)
    public static let maxContentHeightFraction: CGFloat = 0.5
    public static let overshootMargin: CGFloat = 60
    public static let screenEdgeMargin: CGFloat = 60
    public static let navigationSideMinWidth: CGFloat = 80
    public static let pillLeadingWidth: CGFloat = 36
    public static let pillTrailingMaxWidth: CGFloat = 220
    public static let pillTextPadding: CGFloat = 10
    public static var pillFont: NSFont { .systemFont(ofSize: 12, weight: .medium) }

    public let screenFrame: CGRect
    public let notchSize: CGSize
    public let hasHardwareNotch: Bool
    public let contentScale: CGFloat

    public init(screenFrame: CGRect, notchSize: CGSize, hasHardwareNotch: Bool, contentScale: CGFloat = 1) {
        self.screenFrame = screenFrame
        self.notchSize = notchSize
        self.hasHardwareNotch = hasHardwareNotch
        self.contentScale = contentScale
    }

    public func scaled(by contentScale: CGFloat) -> NotchGeometry {
        NotchGeometry(screenFrame: screenFrame, notchSize: notchSize, hasHardwareNotch: hasHardwareNotch, contentScale: contentScale)
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

    public var largestContentSize: CGSize {
        guard screenFrame.width > 0 else { return Self.maxContentSize }
        return CGSize(
            width: max(min(Self.maxContentSize.width, screenFrame.width - 2 * Self.screenEdgeMargin), Self.minContentSize.width),
            height: max(min(Self.maxContentSize.height, screenFrame.height * Self.maxContentHeightFraction), Self.minContentSize.height)
        )
    }

    public var minContentWidth: CGFloat {
        max(Self.minContentSize.width, notchSize.width + 2 * Self.navigationSideMinWidth)
    }

    public func contentSize(for requested: CGSize?) -> CGSize {
        guard let requested, requested.width.isFinite, requested.height.isFinite else {
            return contentSize(for: Self.defaultContentSize)
        }
        let largest = largestContentSize
        return CGSize(
            width: min(max(requested.width * contentScale, minContentWidth), largest.width),
            height: min(max(requested.height * contentScale, Self.minContentSize.height), largest.height)
        )
    }

    public func navigationSideWidth(for contentSize: CGSize? = nil) -> CGFloat {
        (expandedShapeSize(for: contentSize).width - notchSize.width) / 2
    }

    public func expandedShapeSize(for contentSize: CGSize? = nil) -> CGSize {
        let content = self.contentSize(for: contentSize)
        return CGSize(
            width: max(content.width, notchSize.width),
            height: notchSize.height + content.height
        )
    }

    public var largestExpandedShapeSize: CGSize {
        expandedShapeSize(for: largestContentSize)
    }

    public func pillTrailingWidth(for text: String, contentSize: CGSize? = nil) -> CGFloat {
        let textWidth = (text as NSString).size(withAttributes: [.font: Self.pillFont]).width
        return min(ceil(textWidth) + 2 * Self.pillTextPadding, Self.pillTrailingMaxWidth, navigationSideWidth(for: contentSize))
    }

    public func pillTrailingWidth(for pill: PillStatus, contentSize: CGSize? = nil) -> CGFloat {
        pill.artwork == nil ? pillTrailingWidth(for: pill.text, contentSize: contentSize) : Self.pillLeadingWidth
    }

    public func pillShapeSize(for pill: PillStatus, contentSize: CGSize? = nil) -> CGSize {
        CGSize(
            width: notchSize.width + Self.pillLeadingWidth + pillTrailingWidth(for: pill, contentSize: contentSize),
            height: notchSize.height
        )
    }

    public func pillShapeOffset(for pill: PillStatus, contentSize: CGSize? = nil) -> CGFloat {
        (pillTrailingWidth(for: pill, contentSize: contentSize) - Self.pillLeadingWidth) / 2
    }

    public func expandedShapeFrame(for contentSize: CGSize? = nil) -> CGRect {
        let size = expandedShapeSize(for: contentSize)
        return CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
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
}
