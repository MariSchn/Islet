import AppKit
import Observation
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

@MainActor
@Observable
public final class NotchController {
    public private(set) var geometry: NotchGeometry
    public private(set) var isExpanded = false
    public var isHovering = false {
        didSet { scheduleHoverUpdate() }
    }
    public var isDragTargeted = false {
        didSet {
            if isDragTargeted, !oldValue {
                switchToDropTargetIfWanted()
            }
            scheduleHoverUpdate()
        }
    }

    public var switchesToDropTargetOnDrag: Bool {
        get { settings.switchesToDropTargetOnDrag }
        set { settings.switchesToDropTargetOnDrag = newValue }
    }

    public let settings: AppSettings
    public var pill: PillStatus?
    public private(set) var screenSize: CGSize?

    public var expandedShapeSize: CGSize {
        geometry.expandedShapeSize(for: screenSize)
    }

    public var expandedShapeFrame: CGRect {
        geometry.expandedShapeFrame(for: screenSize)
    }

    public var animation: NotchAnimation {
        get { settings.animation }
        set { settings.animation = newValue }
    }

    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var registry: PluginRegistry?

    public init(settings: AppSettings, geometry: NotchGeometry = .placeholder) {
        self.settings = settings
        self.geometry = geometry
    }

    public func update(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    public func attach(_ registry: PluginRegistry) {
        self.registry = registry
        observeRegistry()
    }

    private func switchToDropTargetIfWanted() {
        guard switchesToDropTargetOnDrag, let target = registry?.preferredDropTarget else { return }
        registry?.select(target.id)
    }

    private func observeRegistry() {
        guard let registry else { return }
        withObservationTracking {
            pill = registry.activePill
            screenSize = registry.selectedScreenSize
        } onChange: {
            Task { @MainActor [weak self] in
                self?.observeRegistry()
            }
        }
    }

    public func dragEnded(pointerInside: Bool) {
        isDragTargeted = false
        isHovering = pointerInside
    }

    public func expand() {
        hoverTask?.cancel()
        isExpanded = true
    }

    public func collapse() {
        hoverTask?.cancel()
        isExpanded = false
    }

    private var wantsExpansion: Bool {
        isHovering || isDragTargeted
    }

    private func scheduleHoverUpdate() {
        hoverTask?.cancel()
        let target = wantsExpansion
        guard target != isExpanded else { return }
        if isDragTargeted {
            isExpanded = true
            return
        }
        let delay = target ? animation.expandDelay : animation.collapseDelay
        hoverTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.wantsExpansion == target else { return }
            self.isExpanded = target
        }
    }
}
