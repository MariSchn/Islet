import CoreGraphics
import Testing
import IsletCore

@Suite(.serialized)
@MainActor
struct NotchControllerTests {
    let expandDelay: Duration = .milliseconds(60)
    let collapseDelay: Duration = .milliseconds(120)
    let settle: Duration = .milliseconds(300)

    func makeController() -> NotchController {
        let controller = NotchController()
        controller.animation.expandDelay = expandDelay
        controller.animation.collapseDelay = collapseDelay
        return controller
    }

    @Test func hoverExpandsAfterDelayAndLeavingCollapses() async throws {
        let controller = makeController()

        controller.isHovering = true
        #expect(!controller.isExpanded)
        try await Task.sleep(for: settle)
        #expect(controller.isExpanded)

        controller.isHovering = false
        #expect(controller.isExpanded)
        try await Task.sleep(for: settle)
        #expect(!controller.isExpanded)
    }

    @Test func briefHoverDoesNotExpand() async throws {
        let controller = makeController()

        controller.isHovering = true
        controller.isHovering = false
        try await Task.sleep(for: settle)

        #expect(!controller.isExpanded)
    }

    @Test func briefLeaveDoesNotCollapse() async throws {
        let controller = makeController()
        controller.expand()

        controller.isHovering = false
        controller.isHovering = true
        try await Task.sleep(for: settle)

        #expect(controller.isExpanded)
    }

    @Test func collapseWaitsLongerThanExpand() async throws {
        let controller = makeController()

        controller.isHovering = true
        try await Task.sleep(for: expandDelay * 2)
        #expect(controller.isExpanded)

        controller.isHovering = false
        try await Task.sleep(for: expandDelay * 2 / 3)
        #expect(controller.isExpanded)
        try await Task.sleep(for: settle)
        #expect(!controller.isExpanded)
    }

    @Test func explicitCollapseCancelsPendingExpand() async throws {
        let controller = makeController()

        controller.isHovering = true
        controller.collapse()
        try await Task.sleep(for: settle)

        #expect(!controller.isExpanded)
    }

    @Test func mirrorsRegistryPillIncludingPluginsRegisteredLater() async throws {
        let harness = Harness()
        let registry = harness.makeRegistry()
        let controller = makeController()
        controller.mirrorPill(from: registry)
        #expect(controller.pill == nil)

        let stub = try await harness.registerStub(in: registry)
        stub.context.pillStatus = PillStatus(text: "later", priority: .urgent)
        await Task.yield()
        #expect(controller.pill?.text == "later")

        await registry.setEnabled(false, for: "test.stub")
        await Task.yield()
        #expect(controller.pill == nil)
    }
}
