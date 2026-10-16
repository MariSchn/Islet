import AppKit
import IsletCore
import SwiftUI

@MainActor
public final class NotchDisplayManager {
    private let settings: AppSettings
    private let makePanel: (NotchDisplay) -> NotchPanel
    private var panels: [NotchPanel] = []
    private var pendingRelayout: Task<Void, Never>?
    private var isLocked = false

    public init(settings: AppSettings, makePanel: @escaping (NotchDisplay) -> NotchPanel) {
        self.settings = settings
        self.makePanel = makePanel
    }

    public var controllers: [NotchController] {
        panels.map(\.controller)
    }

    public func toggleNotch(at point: CGPoint) {
        if panels.contains(where: { $0.controller.isExpanded }) {
            panels.forEach { $0.controller.collapse() }
            return
        }
        let panel = panels.first { panel in
            let frame = panel.controller.screenGeometry.screenFrame
            return (frame.minX...frame.maxX).contains(point.x) && (frame.minY...frame.maxY).contains(point.y)
        } ?? panels.first
        panel?.expandPinned()
    }

    public func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(sessionDidLock), name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(sessionDidUnlock), name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(sessionDidLock), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionDidUnlock), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        observePlacement()
        relayout()
    }

    private func observePlacement() {
        withObservationTracking {
            _ = settings.displayPlacement
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.relayout()
                self?.observePlacement()
            }
        }
    }

    @objc private func sessionDidLock() {
        isLocked = true
        panels.forEach { $0.hide() }
    }

    @objc private func sessionDidUnlock() {
        isLocked = false
        relayout()
    }

    @objc private func screenParametersDidChange() {
        pendingRelayout?.cancel()
        pendingRelayout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.relayout()
        }
    }

    public func relayout() {
        let wanted = settings.displayPlacement.displays(among: NotchDisplay.connected())
        let wantedIDs = Set(wanted.map(\.id))
        for panel in panels where !wantedIDs.contains(panel.display.id) {
            panel.hide()
        }
        panels.removeAll { !wantedIDs.contains($0.display.id) }
        for display in wanted where !panels.contains(where: { $0.display.id == display.id }) {
            panels.append(makePanel(display))
        }
        for panel in panels {
            if isLocked {
                panel.hide()
            } else {
                panel.show()
            }
        }
    }
}
