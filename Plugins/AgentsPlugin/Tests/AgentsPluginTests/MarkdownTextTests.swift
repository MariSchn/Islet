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
}
