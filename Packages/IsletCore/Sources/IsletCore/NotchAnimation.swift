import SwiftUI

public struct NotchAnimation: Sendable, Equatable, Codable {
    public enum Curve: Sendable, Equatable, Codable {
        case easeOut
        case spring(dampingFraction: Double)
    }

    public var curve: Curve
    public var expandDuration: Double
    public var collapseDuration: Double
    public var expandDelay: Duration
    public var collapseDelay: Duration

    public init(
        curve: Curve,
        expandDuration: Double,
        collapseDuration: Double,
        expandDelay: Duration,
        collapseDelay: Duration
    ) {
        self.curve = curve
        self.expandDuration = expandDuration
        self.collapseDuration = collapseDuration
        self.expandDelay = expandDelay
        self.collapseDelay = collapseDelay
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.default
        curve = (try? container.decodeIfPresent(Curve.self, forKey: .curve)) ?? fallback.curve
        expandDuration = (try? container.decodeIfPresent(Double.self, forKey: .expandDuration)) ?? fallback.expandDuration
        collapseDuration = (try? container.decodeIfPresent(Double.self, forKey: .collapseDuration)) ?? fallback.collapseDuration
        expandDelay = (try? container.decodeIfPresent(Duration.self, forKey: .expandDelay)) ?? fallback.expandDelay
        collapseDelay = (try? container.decodeIfPresent(Duration.self, forKey: .collapseDelay)) ?? fallback.collapseDelay
    }

    public static let `default` = NotchAnimation(
        curve: .easeOut,
        expandDuration: 0.5,
        collapseDuration: 0.5,
        expandDelay: .milliseconds(40),
        collapseDelay: .milliseconds(60)
    )

    public func animation(expanding: Bool) -> Animation {
        let duration = expanding ? expandDuration : collapseDuration
        switch curve {
        case .easeOut:
            return expanding
                ? .timingCurve(0.16, 1, 0.3, 1, duration: duration)
                : .timingCurve(0.05, 1, 0.15, 1, duration: duration)
        case .spring(let dampingFraction):
            return .spring(response: duration, dampingFraction: dampingFraction)
        }
    }
}

private struct NotchAnimationKey: EnvironmentKey {
    static let defaultValue = NotchAnimation.default.animation(expanding: true)
}

extension EnvironmentValues {
    public var notchAnimation: Animation {
        get { self[NotchAnimationKey.self] }
        set { self[NotchAnimationKey.self] = newValue }
    }
}
