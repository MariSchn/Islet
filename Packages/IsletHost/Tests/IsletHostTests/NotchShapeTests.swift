import SwiftUI
import Testing
import IsletCore
import IsletHost

struct NotchShapeTests {
    @Test func pathFlaresOutwardAtTheTopByTopRadius() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 40)
        let bounds = NotchShape(bottomRadius: 12, topRadius: 8).path(in: rect).boundingRect

        #expect(bounds.minX == -8)
        #expect(bounds.maxX == 208)
        #expect(bounds.minY == 0)
        #expect(bounds.maxY == 40)
    }

    @Test func radiiAreClampedForSmallRects() {
        let rect = CGRect(x: 0, y: 0, width: 20, height: 10)
        let bounds = NotchShape(bottomRadius: 50, topRadius: 50).path(in: rect).boundingRect

        #expect(bounds.minX == -5)
        #expect(bounds.maxX == 25)
        #expect(bounds.height == 10)
    }
}
