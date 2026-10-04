import Foundation

enum TranscriptReader {
    static let tailSize: UInt64 = 512 << 10

    static func lastPrompt(at path: String) -> String? {
        lastMatch(at: path, prompt(in:))
    }

    static func lastAntigravityPrompt(at path: String) -> String? {
        lastMatch(at: path, antigravityPrompt(in:))
    }

    private static func lastMatch(at path: String, _ match: (Data) -> String?) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd(),
              (try? handle.seek(toOffset: end > tailSize ? end - tailSize : 0)) != nil,
              let data = try? handle.readToEnd()
        else { return nil }
        for line in data.split(separator: UInt8(ascii: "\n")).reversed() {
            if let prompt = match(Data(line)) { return prompt }
        }
        return nil
    }

    static func antigravityPrompt(in line: Data) -> String? {
        guard let entry = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              entry["type"] as? String == "USER_INPUT",
              let content = entry["content"] as? String,
              let start = content.range(of: "<USER_REQUEST>"),
              let end = content.range(of: "</USER_REQUEST>", range: start.upperBound..<content.endIndex)
        else { return nil }
        let trimmed = content[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func prompt(in line: Data) -> String? {
        guard let entry = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              entry["type"] as? String == "user",
              entry["isMeta"] as? Bool != true,
              entry["isSidechain"] as? Bool != true,
              entry["isCompactSummary"] as? Bool != true,
              entry["isVisibleInTranscriptOnly"] as? Bool != true,
              let message = entry["message"] as? [String: Any]
        else { return nil }
        let text: String
        if let content = message["content"] as? String {
            text = content
        } else if let blocks = message["content"] as? [[String: Any]], !blocks.contains(where: { $0["type"] as? String == "tool_result" }) {
            text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
        } else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("<"), !trimmed.hasPrefix("[Request interrupted") else { return nil }
        return trimmed
    }
}
