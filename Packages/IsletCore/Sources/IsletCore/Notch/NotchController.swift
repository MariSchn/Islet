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
    public private(set) var screenGeometry: NotchGeometry
    public var geometry: NotchGeometry {
        screenGeometry.scaled(by: settings.notchSize.scale)
    }
    public private(set) var isExpanded = false {
        didSet {
            if !isExpanded {
                hoverHoldSize = nil
            } else {
                dismissAnnouncement()
            }
        }
    }
    public private(set) var announcement: PillAnnouncement?
    public var announcementDuration: Duration = .seconds(4)
    public private(set) var hoverHoldSize: CGSize?
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
    public var contentSize: CGSize? {
        registry?.selectedContentSize
    }

    public var expandedShapeSize: CGSize {
        geometry.expandedShapeSize(for: contentSize)
    }

    public var expandedShapeFrame: CGRect {
        geometry.expandedShapeFrame(for: contentSize)
    }

    public var expandedHoverSize: CGSize {
        guard let hoverHoldSize else { return expandedShapeSize }
        return Self.union(hoverHoldSize, expandedShapeSize)
    }

    public var navigationSideWidth: CGFloat {
        geometry.navigationSideWidth(for: contentSize)
    }

    public var animation: NotchAnimation {
        get { settings.animation }
        set { settings.animation = newValue }
    }

    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var announcementTask: Task<Void, Never>?
    @ObservationIgnored private var seenAnnouncementIDs: Set<UUID> = []
    @ObservationIgnored private var registry: PluginRegistry?
    @ObservationIgnored private var pillHolderID: String?
    @ObservationIgnored private var trackedExpandedShapeSize: CGSize = .zero
    @ObservationIgnored private let pointerLocation: @MainActor () -> CGPoint

    public init(
        settings: AppSettings,
        geometry: NotchGeometry = .placeholder,
        pointerLocation: @escaping @MainActor () -> CGPoint = { NSEvent.mouseLocation }
    ) {
        self.settings = settings
        self.screenGeometry = geometry
        self.pointerLocation = pointerLocation
    }

    public func update(geometry: NotchGeometry) {
        screenGeometry = geometry
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
        var announcements: [PillAnnouncement] = []
        withObservationTracking {
            let heldID = isExpanded ? nil : pillHolderID
            pill = registry.activePill(settings.pillSelection, keeping: heldID)
            pillHolderID = registry.pillHolder(settings.pillSelection, keeping: heldID)
            trackedExpandedShapeSize = expandedShapeSize
            announcements = registry.announcements
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.holdHoverRegionIfShapeLeftPointer(previousSize: self.trackedExpandedShapeSize)
                self.observeRegistry()
            }
        }
        receive(announcements)
    }

    private func receive(_ announcements: [PillAnnouncement]) {
        let fresh = announcements.filter { !seenAnnouncementIDs.contains($0.id) }
        seenAnnouncementIDs = Set(announcements.map(\.id))
        guard let latest = fresh.max(by: { $0.priority < $1.priority }), !isExpanded else { return }
        if let current = announcement, current.priority > latest.priority { return }
        announcement = latest
        announcementTask?.cancel()
        let duration = announcementDuration
        announcementTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.announcement = nil
        }
    }

    public func dismissAnnouncement() {
        announcementTask?.cancel()
        announcement = nil
    }

    private func holdHoverRegionIfShapeLeftPointer(previousSize: CGSize) {
        guard isExpanded, previousSize != expandedShapeSize else { return }
        if isPointerInsideExpandedShape {
            hoverHoldSize = nil
        } else {
            hoverHoldSize = hoverHoldSize.map { Self.union($0, previousSize) } ?? previousSize
        }
    }

    public func pointerEnteredShape() {
        guard isPointerInsideExpandedShape else { return }
        hoverHoldSize = nil
    }

    private var isPointerInsideExpandedShape: Bool {
        expandedShapeFrame.contains(pointerLocation())
    }

    private static func union(_ lhs: CGSize, _ rhs: CGSize) -> CGSize {
        CGSize(width: max(lhs.width, rhs.width), height: max(lhs.height, rhs.height))
    }

    @discardableResult
    public func navigate(_ direction: NavigationDirection) -> Bool {
        guard isExpanded else { return false }
        return registry?.selectNeighbor(direction) ?? false
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
