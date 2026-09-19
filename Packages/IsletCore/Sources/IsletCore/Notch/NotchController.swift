import AppKit
import Observation
import SwiftUI

public struct NotchAnimation: Sendable, Equatable {
    public enum Curve: Sendable, Equatable {
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

@MainActor
@Observable
public final class NotchController {
    public private(set) var geometry: NotchGeometry
    public private(set) var isExpanded = false
    public var isHovering = false {
        didSet { scheduleHoverUpdate() }
    }

    public var animation: NotchAnimation = .default

    @ObservationIgnored private var hoverTask: Task<Void, Never>?

    public init(geometry: NotchGeometry = .placeholder) {
        self.geometry = geometry
    }

    public func update(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    public func expand() {
        hoverTask?.cancel()
        isExpanded = true
    }

    public func collapse() {
        hoverTask?.cancel()
        isExpanded = false
    }

    private func scheduleHoverUpdate() {
        hoverTask?.cancel()
        let target = isHovering
        guard target != isExpanded else { return }
        let delay = target ? animation.expandDelay : animation.collapseDelay
        hoverTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.isHovering == target else { return }
            self.isExpanded = target
        }
    }
}
