import Foundation
import Testing
@testable import ShelfPlugin

struct ShelfSelectionTests {
    let first = UUID()
    let second = UUID()
    let third = UUID()
    let fourth = UUID()

    private var displayOrder: [UUID] { [first, second, third, fourth] }

    @Test func clickSelectsOnlyThatItem() {
        var selection = ShelfSelection()
        selection.click(first)
        selection.click(second)
        #expect(selection.ids == [second])
        #expect(selection.anchor == second)
    }

    @Test func commandClickToggles() {
        var selection = ShelfSelection()
        selection.click(first)
        selection.commandClick(third)
        #expect(selection.ids == [first, third])
        #expect(selection.anchor == third)
        selection.commandClick(third)
        #expect(selection.ids == [first])
        #expect(selection.anchor == third)
        selection.commandClick(first)
        #expect(selection.ids.isEmpty)
    }

    @Test func shiftClickSelectsTheRangeInBothDirections() {
        var selection = ShelfSelection()
        selection.click(second)
        selection.shiftClick(fourth, displayOrder: displayOrder)
        #expect(selection.ids == [second, third, fourth])
        #expect(selection.anchor == second)

        selection.shiftClick(first, displayOrder: displayOrder)
        #expect(selection.ids == [first, second])
        #expect(selection.anchor == second)
    }

    @Test func shiftClickUsesTheCommandClickAnchor() {
        var selection = ShelfSelection()
        selection.click(first)
        selection.commandClick(third)
        selection.shiftClick(first, displayOrder: displayOrder)
        #expect(selection.ids == [first, second, third])
        #expect(selection.anchor == third)
    }

    @Test func clearEmptiesTheSelection() {
        var selection = ShelfSelection()
        selection.click(first)
        selection.commandClick(third)
        selection.clear()
        #expect(selection.ids.isEmpty)
        #expect(selection.anchor == nil)
    }

    @Test func removedItemsLeaveTheSelection() {
        var selection = ShelfSelection()
        selection.click(first)
        selection.commandClick(second)
        selection.commandClick(third)
        selection.remove([second])
        #expect(selection.ids == [first, third])
        #expect(selection.anchor == third)

        selection.remove([third])
        #expect(selection.ids == [first])
        #expect(selection.anchor == nil)

        selection.click(first)
        selection.commandClick(fourth)
        selection.remove([first, fourth])
        #expect(selection.ids.isEmpty)
        #expect(selection.anchor == nil)
    }
}
