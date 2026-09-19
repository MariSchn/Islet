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
        let controller = NotchController(settings: AppSettings())
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

    @Test func dragTargetExpandsImmediatelyAndCollapsesAfterLeaving() async throws {
        let controller = makeController()

        controller.isDragTargeted = true
        #expect(controller.isExpanded)

        controller.isDragTargeted = false
        #expect(controller.isExpanded)
        try await Task.sleep(for: settle)
        #expect(!controller.isExpanded)
    }

    @Test func hoverKeepsNotchOpenAfterDragLeaves() async throws {
        let controller = makeController()
        controller.isHovering = true
        controller.isDragTargeted = true

        controller.isDragTargeted = false
        try await Task.sleep(for: settle)

        #expect(controller.isExpanded)
    }

    @Test func dragEndResyncsHoverFromPointerLocation() async throws {
        let controller = makeController()
        controller.isHovering = true
        controller.isDragTargeted = true

        controller.dragEnded(pointerInside: false)
        try await Task.sleep(for: settle)
        #expect(!controller.isHovering)
        #expect(!controller.isExpanded)

        controller.isDragTargeted = true
        controller.dragEnded(pointerInside: true)
        try await Task.sleep(for: settle)
        #expect(controller.isHovering)
        #expect(controller.isExpanded)
    }

    @Test func mirrorsRegistryPillIncludingPluginsRegisteredLater() async throws {
        let harness = Harness()
        let registry = harness.makeRegistry()
        let controller = makeController()
        controller.attach(registry)
        #expect(controller.pill == nil)

        let stub = try await harness.registerStub(in: registry)
        stub.context.pillStatus = PillStatus(text: "later", priority: .urgent)
        await Task.yield()
        #expect(controller.pill?.text == "later")

        await registry.setEnabled(false, for: "test.stub")
        await Task.yield()
        #expect(controller.pill == nil)
    }

    @Test func mirrorsSelectedPluginScreenSize() async throws {
        let harness = Harness()
        let registry = harness.makeRegistry()
        let controller = makeController()
        controller.attach(registry)
        let stub = try await harness.registerStub(in: registry)
        try await harness.registerSecond(in: registry)
        #expect(controller.screenSize == nil)
        #expect(controller.expandedShapeSize == controller.geometry.expandedShapeSize)

        stub.context.screenSize = CGSize(width: 400, height: 100)
        await Task.yield()
        #expect(controller.screenSize == CGSize(width: 400, height: 100))
        #expect(controller.expandedShapeSize.width == 400)

        registry.select("test.second")
        await Task.yield()
        #expect(controller.screenSize == nil)

        registry.select("test.stub")
        await Task.yield()
        #expect(controller.screenSize == CGSize(width: 400, height: 100))
    }

    @Test func dragSwitchesToFirstDropAcceptingPluginUnlessDisabled() async throws {
        let harness = Harness()
        let registry = harness.makeRegistry()
        let controller = makeController()
        controller.attach(registry)
        try await harness.registerStub(in: registry)
        try await harness.registerSecond(in: registry) { $0.acceptsFileDrops = true }
        #expect(registry.selectedID == "test.stub")

        controller.isDragTargeted = true
        #expect(registry.selectedID == "test.second")

        controller.isDragTargeted = false
        registry.select("test.stub")
        controller.switchesToDropTargetOnDrag = false
        controller.isDragTargeted = true
        #expect(registry.selectedID == "test.stub")
    }
}
