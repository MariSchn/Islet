import Foundation
import Testing
@testable import ShelfPlugin

struct ShelfItemNamingTests {
    @Test func textUsesTheFirstNonEmptyLine() {
        #expect(ShelfItemNaming.textFileName(for: "\n  \nHello\nWorld") == "Hello.txt")
    }

    @Test func longTextIsTruncatedToFortyCharacters() {
        let name = ShelfItemNaming.textFileName(for: String(repeating: "a", count: 100))
        #expect(name == String(repeating: "a", count: 40) + ".txt")
    }

    @Test func emptyTextIsNamedText() {
        #expect(ShelfItemNaming.textFileName(for: "") == "Text.txt")
        #expect(ShelfItemNaming.textFileName(for: " \n\t ") == "Text.txt")
    }

    @Test func slashesAndColonsAreReplaced() {
        #expect(ShelfItemNaming.textFileName(for: "a/b:c") == "a-b-c.txt")
    }

    @Test func linksUseTheHost() {
        #expect(ShelfItemNaming.linkFileName(for: URL(string: "https://github.com/x/y")!) == "github.com.webloc")
    }

    @Test func imagesUseTheDateAndTime() {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 3
        components.hour = 9
        components.minute = 5
        components.second = 7
        let date = Calendar.current.date(from: components)!
        #expect(ShelfItemNaming.imageFileName(date: date) == "Image 2026-10-03 09.05.07.png")
    }
}
