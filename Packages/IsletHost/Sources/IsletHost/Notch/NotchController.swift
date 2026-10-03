import AppKit
import IsletCore
import Observation
import SwiftUI

@MainActor
@Observable
public final class NotchController {
    public private(set) var screenGeometry: NotchGeometry
    public var geometry: NotchGeometry {
        screenGeometry.scaled(by: settings.notchSize.scale)
    }
    public private(set) var isExpanded = false {
        didSet {
            if isExpanded != oldValue {
                registry?.setNotchExpanded(isExpanded, by: self)
            }
            if !isExpanded {
                hoverHoldSize = nil
                isPinned = false
            } else {
                dismissAnnouncement()
                if !oldValue, let pillOwnerID {
                    registry?.select(pillOwnerID)
                }
            }
        }
    }
    public private(set) var announcement: PillAnnouncement?
    public var announcementDuration: Duration = .seconds(4)
    public private(set) var hoverHoldSize: CGSize?
    public private(set) var isPinned = false {
        didSet {
            guard isPinned != oldValue else { return }
            if isPinned {
                installOutsideClickMonitor()
            } else {
                pointerEnteredWhilePinned = false
                removeOutsideClickMonitor()
            }
        }
    }
    public var isHovering = false {
        didSet {
            if isPinned {
                if isHovering {
                    pointerEnteredWhilePinned = true
                } else if pointerEnteredWhilePinned {
                    isPinned = false
                }
            }
            scheduleHoverUpdate()
        }
    }
    public var isDragTargeted = false {
        didSet {
            scheduleHoverUpdate()
            if isDragTargeted, !oldValue {
                switchToDropTargetIfWanted()
            }
        }
    }

    public var acceptsFileDrops: Bool {
        registry?.preferredDropTarget != nil
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

    public var hidesIdleShape: Bool {
        !isExpanded && pill == nil && announcement == nil && !settings.drawsIdleNotchShape
    }

    public var highlightsHoveredShape: Bool {
        settings.openTrigger == .click && isHovering && !isExpanded && announcement == nil
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
    @ObservationIgnored private var pillOwnerID: String?
    @ObservationIgnored private var trackedExpandedShapeSize: CGSize = .zero
    @ObservationIgnored private let pointerLocation: @MainActor () -> CGPoint
    @ObservationIgnored private var pointerEnteredWhilePinned = false
    @ObservationIgnored nonisolated(unsafe) private var outsideClickMonitor: Any?

    public init(
        settings: AppSettings,
        geometry: NotchGeometry = .placeholder,
        pointerLocation: @escaping @MainActor () -> CGPoint = { NSEvent.mouseLocation }
    ) {
        self.settings = settings
        self.screenGeometry = geometry
        self.pointerLocation = pointerLocation
    }

    deinit {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
    }

    public func update(geometry: NotchGeometry) {
        screenGeometry = geometry
    }

    public func attach(_ registry: PluginRegistry) {
        self.registry = registry
        seenAnnouncementIDs = Set(registry.announcements.map(\.id))
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
            pillOwnerID = isExpanded ? nil : registry.pillOwner(settings.pillSelection, keeping: heldID)
            trackedExpandedShapeSize = expandedShapeSize
            announcements = registry.announcements
        } onChange: { [weak self] in
            Task { @MainActor in
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
        guard isExpanded, isHovering, previousSize != expandedShapeSize else { return }
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

    public func expandPinned() {
        hoverTask?.cancel()
        isPinned = true
        pointerEnteredWhilePinned = isHovering
        isExpanded = true
    }

    public func clicked() {
        guard !isExpanded else { return }
        expand()
    }

    public func collapse() {
        hoverTask?.cancel()
        isExpanded = false
    }

    private var wantsExpansion: Bool {
        isHovering || isDragTargeted || isPinned
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.collapse()
            }
        }
    }

    private func removeOutsideClickMonitor() {
        guard let outsideClickMonitor else { return }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }

    private func scheduleHoverUpdate() {
        hoverTask?.cancel()
        let target = wantsExpansion
        guard target != isExpanded else { return }
        if isDragTargeted {
            isExpanded = true
            return
        }
        if target, settings.openTrigger != .hover { return }
        let delay = target ? animation.expandDelay : animation.collapseDelay
        hoverTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.wantsExpansion == target,
                  !target || self.settings.openTrigger == .hover else { return }
            self.isExpanded = target
        }
    }
}
