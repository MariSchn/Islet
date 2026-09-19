import AppKit
import SwiftUI

@MainActor
public final class NotchPanel: NSPanel {
    private let controller: NotchController
    private var pendingRelayout: Task<Void, Never>?
    private var swipeRecognizer = HorizontalSwipeRecognizer()
    nonisolated(unsafe) private var scrollMonitor: Any?

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
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
            return event
        }
    }

    deinit {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
    }

    private func handleScroll(_ event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return }
        let phase: HorizontalSwipeRecognizer.Phase
        switch event.phase {
        case .began: phase = .began
        case .changed: phase = .changed
        case .ended, .cancelled: phase = .ended
        default: return
        }
        guard event.window === self, !scrollsHorizontally(at: event.locationInWindow) else {
            swipeRecognizer.handle(phase: .ended, deltaX: 0, deltaY: 0)
            return
        }
        if let direction = swipeRecognizer.handle(phase: phase, deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY) {
            controller.navigate(direction)
        }
    }

    private func scrollsHorizontally(at location: NSPoint) -> Bool {
        var view = contentView?.hitTest(location)
        while let current = view {
            if let scrollView = current as? NSScrollView, let document = scrollView.documentView,
               document.frame.width > scrollView.contentView.bounds.width {
                return true
            }
            view = current.superview
        }
        return false
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
