import CoreGraphics
import Testing
@testable import IsletHost

struct PluginCarouselTests {
    @Test func neighboursLineUpEdgeToEdgeOnBothSides() {
        #expect(PluginCarousel.offsets(for: [800, 300, 500], selectedIndex: 1) == [-550, 0, 400])
        #expect(PluginCarousel.offsets(for: [200, 400, 600], selectedIndex: 2) == [-800, -500, 0])
        #expect(PluginCarousel.offsets(for: [600, 400, 200], selectedIndex: 0) == [0, 500, 800])
    }

    @Test func aSinglePluginIsCentered() {
        #expect(PluginCarousel.offsets(for: [420], selectedIndex: 0) == [0])
    }
}
