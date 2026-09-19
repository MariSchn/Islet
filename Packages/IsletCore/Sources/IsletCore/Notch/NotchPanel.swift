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
        appearance = NSAppearance(named: .darkAqua)

        contentView = NotchHostingView(
            controller: controller,
            rootView: NotchView(controller: controller, content: content)
        )

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

    public override var canBecomeKey: Bool { true }
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

@MainActor
private final class NotchHostingView<Content: View>: NSHostingView<Content> {
    private let controller: NotchController

    init(controller: NotchController, rootView: Content) {
        self.controller = controller
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL, .URL, .string, .tiff, .png])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    @available(*, unavailable)
    required init(rootView: Content) { fatalError("use init(controller:rootView:)") }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        controller.isDragTargeted = true
        return super.draggingEntered(sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        controller.dragEnded(pointerInside: isPointerInsideExpandedShape)
        super.draggingExited(sender)
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        controller.dragEnded(pointerInside: isPointerInsideExpandedShape)
        super.draggingEnded(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let accepted = super.performDragOperation(sender)
        controller.dragEnded(pointerInside: isPointerInsideExpandedShape)
        return accepted
    }

    private var isPointerInsideExpandedShape: Bool {
        controller.expandedShapeFrame.contains(NSEvent.mouseLocation)
    }
}
