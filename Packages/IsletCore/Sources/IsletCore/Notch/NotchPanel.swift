import AppKit
import SwiftUI

@MainActor
public final class NotchPanel: NSPanel {
    private let controller: NotchController
    private var pendingRelayout: Task<Void, Never>?

    public init<Content: View>(controller: NotchController, @ViewBuilder content: @escaping () -> Content) {
        self.controller = controller
        super.init(
            contentRect: controller.geometry.panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        contentView = NSHostingView(rootView: NotchView(controller: controller, content: content))

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenParametersDidChange() {
        pendingRelayout?.cancel()
        pendingRelayout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.relayout()
        }
    }

    public override var canBecomeMain: Bool { false }

    public func show() {
        relayout()
        orderFrontRegardless()
    }

    public func relayout() {
        guard let screen = NotchGeometry.preferredScreen() else { return }
        let geometry = NotchGeometry(screen: screen)
        controller.update(geometry: geometry)
        setFrame(geometry.panelFrame, display: true)
    }
}
