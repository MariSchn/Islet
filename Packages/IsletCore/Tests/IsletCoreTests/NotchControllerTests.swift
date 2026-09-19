import CoreGraphics
import Testing
import IsletCore

@MainActor
struct NotchControllerTests {
    func makeController() -> NotchController {
        let geometry = NotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            notchSize: CGSize(width: 196, height: 32),
            hasHardwareNotch: true
        )
        let controller = NotchController(geometry: geometry)
        controller.animation.expandDelay = .milliseconds(30)
        controller.animation.collapseDelay = .milliseconds(30)
        return controller
    }

    @Test func hoverExpandsAfterDelayAndLeavingCollapses() async throws {
        let controller = makeController()

        controller.isHovering = true
        #expect(!controller.isExpanded)
        try await Task.sleep(for: .milliseconds(80))
        #expect(controller.isExpanded)

        controller.isHovering = false
        #expect(controller.isExpanded)
        try await Task.sleep(for: .milliseconds(80))
        #expect(!controller.isExpanded)
    }

    @Test func briefHoverDoesNotExpand() async throws {
        let controller = makeController()

        controller.isHovering = true
        try await Task.sleep(for: .milliseconds(5))
        controller.isHovering = false
        try await Task.sleep(for: .milliseconds(80))

        #expect(!controller.isExpanded)
    }

    @Test func briefLeaveDoesNotCollapse() async throws {
        let controller = makeController()
        controller.expand()

        controller.isHovering = false
        try await Task.sleep(for: .milliseconds(5))
        controller.isHovering = true
        try await Task.sleep(for: .milliseconds(80))

        #expect(controller.isExpanded)
    }

    @Test func explicitCollapseCancelsPendingExpand() async throws {
        let controller = makeController()

        controller.isHovering = true
        controller.collapse()
        try await Task.sleep(for: .milliseconds(80))

        #expect(!controller.isExpanded)
    }
}
