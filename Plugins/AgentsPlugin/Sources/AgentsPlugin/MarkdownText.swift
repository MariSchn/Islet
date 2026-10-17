import SwiftUI

struct MarkdownText: View {
    enum Block: Equatable {
        case heading(String, level: Int)
        case bullet(String)
        case numbered(String, number: String)
        case code(String)
        case paragraph(String)
    }

    let blocks: [Block]

    init(_ markdown: String) {
        blocks = Self.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let text, let level):
                    inline(text)
                        .font(.system(size: level == 1 ? 13 : 12, weight: .semibold))
                        .padding(.top, 2)
                case .bullet(let text):
                    HStack(alignment: .top, spacing: 4) {
                        Text("•")
                        inline(text)
                    }
                    .padding(.leading, 6)
                case .numbered(let text, let number):
                    HStack(alignment: .top, spacing: 4) {
                        Text("\(number).")
                        inline(text)
                    }
                    .padding(.leading, 6)
                case .code(let text):
                    Text(text)
                        .font(.system(size: 10, design: .monospaced))
                        .padding(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.08)))
                case .paragraph(let text):
                    inline(text)
                }
            }
        }
        .font(.system(size: 11))
        .textSelection(.enabled)
    }

    private func inline(_ text: String) -> Text {
        Text(Self.attributed(text))
    }

    static func attributed(_ text: String) -> AttributedString {
        let parsed = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        return parsed.transformingAttributes(\.link) { link in
            if let url = link.value, !["http", "https"].contains(url.scheme?.lowercased()) {
                link.value = nil
            }
        }
    }

    static func parse(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String]?

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }

        for rawLine in markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let lines = code {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    flushParagraph()
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(line)
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
            } else if trimmed.hasPrefix("#") {
                flushParagraph()
                let level = trimmed.prefix { $0 == "#" }.count
                blocks.append(.heading(trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces), level: level))
            } else if let marker = ["- ", "* ", "+ "].first(where: trimmed.hasPrefix) {
                flushParagraph()
                blocks.append(.bullet(String(trimmed.dropFirst(marker.count))))
            } else if let dot = trimmed.firstIndex(of: "."), trimmed[..<dot].allSatisfy(\.isNumber), !trimmed[..<dot].isEmpty, trimmed[trimmed.index(after: dot)...].hasPrefix(" ") {
                flushParagraph()
                blocks.append(.numbered(trimmed[trimmed.index(after: dot)...].trimmingCharacters(in: .whitespaces), number: String(trimmed[..<dot])))
            } else {
                paragraph.append(trimmed)
            }
        }
        if let lines = code {
            blocks.append(.code(lines.joined(separator: "\n")))
        }
        flushParagraph()
        return blocks
    }
}
