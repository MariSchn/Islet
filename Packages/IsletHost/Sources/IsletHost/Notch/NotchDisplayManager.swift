import AppKit
import IsletCore
import SwiftUI

@MainActor
public final class NotchDisplayManager {
    private let settings: AppSettings
    private let makePanel: (NotchDisplay) -> NotchPanel
    private var panels: [NotchPanel] = []
    private var pendingRelayout: Task<Void, Never>?

    public init(settings: AppSettings, makePanel: @escaping (NotchDisplay) -> NotchPanel) {
        self.settings = settings
        self.makePanel = makePanel
    }

    public var controllers: [NotchController] {
        panels.map(\.controller)
    }

    public func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        observePlacement()
        relayout()
    }

    private func observePlacement() {
        withObservationTracking {
            _ = settings.displayPlacement
        } onChange: {
            Task { @MainActor [weak self] in
                self?.relayout()
                self?.observePlacement()
            }
        }
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
            panel.show()
        }
    }
}
