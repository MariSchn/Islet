import CoreGraphics
import IsletCore

public struct HorizontalSwipeRecognizer: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case began
        case changed
        case ended
    }

    public static let defaultThreshold: CGFloat = 40

    public let threshold: CGFloat
    private var travel = CGVector.zero
    private var isTracking = false
    private var hasFired = false

    public init(threshold: CGFloat = Self.defaultThreshold) {
        self.threshold = threshold
    }

    @discardableResult
    public mutating func handle(phase: Phase, deltaX: CGFloat, deltaY: CGFloat) -> NavigationDirection? {
        switch phase {
        case .began:
            travel = .zero
            isTracking = true
            hasFired = false
            return nil
        case .changed:
            guard isTracking, !hasFired else { return nil }
            travel.dx += deltaX
            travel.dy += deltaY
            guard abs(travel.dx) >= threshold, abs(travel.dx) > abs(travel.dy) else { return nil }
            hasFired = true
            return travel.dx < 0 ? .forward : .backward
        case .ended:
            isTracking = false
            hasFired = false
            travel = .zero
            return nil
        }
    }
}
