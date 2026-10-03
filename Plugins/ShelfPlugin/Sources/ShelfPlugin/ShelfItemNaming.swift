import Foundation

enum ShelfItemNaming {
    static let maxTextNameLength = 40

    static func firstLine(of text: String) -> String? {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    static func textFileName(for text: String) -> String {
        let line = firstLine(of: text) ?? ""
        let name = sanitized(String(line.prefix(maxTextNameLength))).trimmingCharacters(in: .whitespaces)
        return (name.isEmpty ? "Text" : name) + ".txt"
    }

    static func linkFileName(for url: URL) -> String {
        sanitized(linkTitle(for: url)) + ".webloc"
    }

    static func linkTitle(for url: URL) -> String {
        url.host(percentEncoded: false) ?? url.absoluteString
    }

    static func imageFileName(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Image \(formatter.string(from: date)).png"
    }

    private static func sanitized(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }
}
