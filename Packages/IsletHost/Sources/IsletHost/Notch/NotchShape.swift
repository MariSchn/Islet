import SwiftUI

public struct NotchShape: Shape {
    public var bottomRadius: CGFloat
    public var topRadius: CGFloat

    public init(bottomRadius: CGFloat = 18, topRadius: CGFloat = 8) {
        self.bottomRadius = bottomRadius
        self.topRadius = topRadius
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, topRadius) }
        set {
            bottomRadius = newValue.first
            topRadius = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        let bottom = min(bottomRadius, rect.height / 2, rect.width / 2)
        let top = min(topRadius, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - top, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + top),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX + top, y: rect.minY),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
