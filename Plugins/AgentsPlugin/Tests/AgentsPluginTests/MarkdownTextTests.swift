import Foundation
import IsletCore
import Testing
@testable import AgentsPlugin

@MainActor
struct MarkdownTextTests {
    @Test func splitsMarkdownIntoBlocks() {
        let blocks = MarkdownText.parse("# Title\n\nSome *text*\nthat wraps\n\n- one\n* two\n1. first\n```\nlet x = 1\n```\n")
        let expected: [MarkdownText.Block] = [
            .heading("Title", level: 1),
            .paragraph("Some *text* that wraps"),
            .bullet("one"),
            .bullet("two"),
            .numbered("first", number: "1"),
            .code("let x = 1"),
        ]
        #expect(blocks == expected)
    }

    @Test func onlyWebLinksStayClickable() {
        let text = MarkdownText.attributed("See [docs](https://example.com), [app](file:///Applications/Calculator.app) and [share](smb://host/share)")
        #expect(text.runs.compactMap(\.link) == [URL(string: "https://example.com")!])
        #expect(String(text.characters) == "See docs, app and share")
    }
}
