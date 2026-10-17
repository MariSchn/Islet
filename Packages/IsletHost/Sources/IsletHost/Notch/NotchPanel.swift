import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public final class NotchPanel: NSPanel {
    public let display: NotchDisplay
    public let controller: NotchController
    private var swipeRecognizer = HorizontalSwipeRecognizer()
    nonisolated(unsafe) private var scrollMonitor: Any?

    public init<Content: View>(display: NotchDisplay, controller: NotchController, @ViewBuilder content: @escaping () -> Content) {
        self.display = display
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
        canHide = false
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)

        contentView = NotchHostingView(
            controller: controller,
            rootView: NotchView(controller: controller, content: content)
        )

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
            return event
        }
        observeExpansion()
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
        let fingerDirection: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        if let direction = swipeRecognizer.handle(phase: phase, deltaX: event.scrollingDeltaX * fingerDirection, deltaY: event.scrollingDeltaY * fingerDirection) {
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

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    public func expandPinned() {
        controller.expandPinned()
        makeKey()
    }

    public override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !(firstResponder is NSTextView), modifiers.isEmpty else {
            super.keyDown(with: event)
            return
        }
        switch Int(event.keyCode) {
        case kVK_LeftArrow: controller.navigate(.backward)
        case kVK_RightArrow: controller.navigate(.forward)
        case kVK_Escape: controller.collapse()
        default:
            if firstResponder !== self {
                super.keyDown(with: event)
            }
        }
    }

    public override func moveLeft(_ sender: Any?) {
        controller.navigate(.backward)
    }

    public override func moveRight(_ sender: Any?) {
        controller.navigate(.forward)
    }

    public override func cancelOperation(_ sender: Any?) {
        controller.collapse()
    }

    private func observeExpansion() {
        withObservationTracking {
            _ = controller.isExpanded
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if !self.controller.isExpanded {
                    self.giveUpKeyFocus()
                }
                self.observeExpansion()
            }
        }
    }

    private func giveUpKeyFocus() {
        guard isKeyWindow, isVisible else { return }
        orderOut(nil)
        orderFrontRegardless()
        NotchSpace.shared.add(self)
    }

    public func show() {
        relayout()
        orderFrontRegardless()
        NotchSpace.shared.add(self)
    }

    public func hide() {
        controller.collapse()
        NotchSpace.shared.remove(self)
        orderOut(nil)
    }

    public func relayout() {
        guard let screen = NSScreen.screens.first(where: { NotchDisplay(screen: $0).id == display.id }) else { return }
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
        let types = (sender.draggingPasteboard.types ?? []).compactMap { UTType($0.rawValue) }
        guard controller.acceptsDrag(of: types) else { return [] }
        // A drag that starts in the notch, such as a download dragged out of it, doesn't switch plugins.
        controller.draggedTypes = sender.draggingSource == nil ? types : []
        controller.isDragTargeted = true
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard controller.isDragTargeted else { return [] }
        return super.draggingUpdated(sender)
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
