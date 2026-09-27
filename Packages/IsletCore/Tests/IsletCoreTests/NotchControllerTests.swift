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

    @Test func pillFollowsSelectionSettingAndSelectedPlugin() async throws {
        let harness = Harness()
        let registry = harness.makeRegistry()
        let controller = makeController()
        controller.attach(registry)
        let stub = try await harness.registerStub(in: registry)
        let second = try await harness.registerSecond(in: registry)
        stub.context.pillStatus = PillStatus(text: "song", priority: .ambient)
        second.context.pillStatus = PillStatus(text: "working", priority: .info)
        await Task.yield()
        #expect(controller.pill?.text == "song")

        registry.select("test.second")
        await Task.yield()
        #expect(controller.pill?.text == "working")

        registry.select("test.stub")
        controller.settings.pillSelection = .mostImportant
        await Task.yield()
        #expect(controller.pill?.text == "working")
    }

    @Test func showsNewAnnouncementsBrieflyWhileCollapsed() async throws {
        let harness = Harness()
        let registry = harness.makeRegistry()
        let controller = makeController()
        controller.announcementDuration = .milliseconds(150)
        controller.attach(registry)
        let stub = try await harness.registerStub(in: registry)

        let first = PillAnnouncement(text: "Build finished")
        stub.context.announce(first)
        await Task.yield()
        #expect(controller.announcement == first)

        try await Task.sleep(for: settle)
        #expect(controller.announcement == nil)

        stub.context.pillStatus = PillStatus(text: "unrelated change")
        await Task.yield()
        #expect(controller.announcement == nil)

        let second = PillAnnouncement(text: "Needs you")
        stub.context.announce(second)
        await Task.yield()
        #expect(controller.announcement == second)
        controller.expand()
        #expect(controller.announcement == nil)

        stub.context.announce(PillAnnouncement(text: "While open"))
        await Task.yield()
        #expect(controller.announcement == nil)
        controller.collapse()
        await Task.yield()
        #expect(controller.announcement == nil)
    }

    @Test func lessImportantAnnouncementsWaitForMoreImportantOnes() async throws {
        let harness = Harness()
        let registry = harness.makeRegistry()
        let controller = makeController()
        controller.announcementDuration = .milliseconds(150)
        controller.attach(registry)
        let stub = try await harness.registerStub(in: registry)

        let urgent = PillAnnouncement(text: "Needs you", priority: .attention)
        stub.context.announce(urgent)
        await Task.yield()
        stub.context.announce(PillAnnouncement(text: "Finished"))
        await Task.yield()
        #expect(controller.announcement == urgent)

        try await Task.sleep(for: settle)
        let later = PillAnnouncement(text: "Finished later")
        stub.context.announce(later)
        await Task.yield()
        #expect(controller.announcement == later)
    }

    @Test func announcementsFromDisabledPluginsAreDropped() async throws {
        let harness = Harness()
        let registry = harness.makeRegistry()
        let controller = makeController()
        controller.attach(registry)
        let stub = try await harness.registerStub(in: registry)

        await registry.setEnabled(false, for: "test.stub")
        stub.context.announce(PillAnnouncement(text: "While disabled"))
        await registry.setEnabled(true, for: "test.stub")
        await Task.yield()
        #expect(controller.announcement == nil)
        #expect(registry.announcements.isEmpty)
    }

    @Test func mirrorsSelectedPluginContentSize() async throws {
        let harness = Harness()
        let registry = harness.makeRegistry()
        let controller = makeController()
        controller.attach(registry)
        let stub = try await harness.registerStub(in: registry)
        try await harness.registerSecond(in: registry)
        #expect(controller.contentSize == nil)
        #expect(controller.expandedShapeSize == controller.geometry.expandedShapeSize())

        stub.context.contentSize = CGSize(width: 400, height: 100)
        await Task.yield()
        #expect(controller.contentSize == CGSize(width: 400, height: 100))
        #expect(controller.expandedShapeSize.width == 400)

        registry.select("test.second")
        await Task.yield()
        #expect(controller.contentSize == nil)

        registry.select("test.stub")
        await Task.yield()
        #expect(controller.contentSize == CGSize(width: 400, height: 100))

        await registry.setEnabled(false, for: "test.stub")
        await Task.yield()
        #expect(controller.contentSize == nil)
    }

    @Test func keepsPreviousHoverRegionWhenShapeShrinksAwayFromPointer() async throws {
        let harness = Harness()
        let registry = harness.makeRegistry()
        var pointer = CGPoint(x: 10_000, y: 10_000)
        let controller = NotchController(settings: AppSettings()) { pointer }
        controller.attach(registry)
        let stub = try await harness.registerStub(in: registry)
        let second = try await harness.registerSecond(in: registry)
        stub.context.contentSize = CGSize(width: 800, height: 400)
        second.context.contentSize = CGSize(width: 300, height: 100)
        await Task.yield()
        let largeSize = controller.geometry.expandedShapeSize(for: CGSize(width: 800, height: 400))
        let smallSize = controller.geometry.expandedShapeSize(for: CGSize(width: 300, height: 100))

        registry.select("test.second")
        await Task.yield()
        #expect(controller.hoverHoldSize == nil)
        #expect(controller.expandedHoverSize == smallSize)

        registry.select("test.stub")
        await Task.yield()
        controller.expand()
        controller.isHovering = true
        registry.select("test.second")
        await Task.yield()
        #expect(controller.hoverHoldSize == largeSize)
        #expect(controller.expandedHoverSize == largeSize)

        second.context.contentSize = CGSize(width: 900, height: 100)
        await Task.yield()
        #expect(controller.expandedHoverSize == CGSize(width: 900, height: largeSize.height))

        controller.pointerEnteredShape()
        #expect(controller.hoverHoldSize != nil)

        pointer = CGPoint(x: 0, y: -10)
        controller.pointerEnteredShape()
        #expect(controller.hoverHoldSize == nil)

        registry.select("test.stub")
        await Task.yield()
        second.context.contentSize = CGSize(width: 300, height: 100)
        registry.select("test.second")
        await Task.yield()
        #expect(controller.hoverHoldSize == nil)

        pointer = CGPoint(x: 10_000, y: 10_000)
        registry.select("test.stub")
        await Task.yield()
        registry.select("test.second")
        await Task.yield()
        #expect(controller.hoverHoldSize == largeSize)
        controller.collapse()
        #expect(controller.hoverHoldSize == nil)
    }

    @Test func navigateOnlySwitchesPluginsWhileExpanded() async throws {
        let harness = Harness()
        let registry = harness.makeRegistry()
        let controller = makeController()
        controller.expand()
        #expect(!controller.navigate(.forward))
        controller.collapse()
        controller.attach(registry)
        try await harness.registerStub(in: registry)
        try await harness.registerSecond(in: registry)

        #expect(!controller.navigate(.forward))
        #expect(registry.selectedID == "test.stub")

        controller.expand()
        #expect(controller.navigate(.forward))
        #expect(registry.selectedID == "test.second")
        #expect(!controller.navigate(.forward))
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
