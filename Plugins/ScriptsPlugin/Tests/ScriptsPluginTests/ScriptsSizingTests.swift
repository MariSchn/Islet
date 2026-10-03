import Testing
@testable import ScriptsPlugin

@MainActor
struct ScriptsSizingTests {
    @Test func emptyStateHasAFixedHeight() {
        let size = ScriptsPlugin.contentSize(activityCount: 0)
        #expect(size.width == 420)
        #expect(size.height == ScriptsPlugin.emptyHeight)
    }

    @Test func eachRowAddsItsHeight() {
        #expect(ScriptsPlugin.contentSize(activityCount: 1).height == 36)
        #expect(ScriptsPlugin.contentSize(activityCount: 3).height == 108)
    }

    @Test func heightStopsGrowingAfterFiveRows() {
        #expect(ScriptsPlugin.contentSize(activityCount: 5).height == 180)
        #expect(ScriptsPlugin.contentSize(activityCount: 6) == ScriptsPlugin.contentSize(activityCount: 5))
        #expect(ScriptsPlugin.contentSize(activityCount: 50) == ScriptsPlugin.contentSize(activityCount: 5))
    }
}
