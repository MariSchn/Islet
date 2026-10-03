import Foundation

struct ActivityEntry: Identifiable, Sendable, Equatable, Codable {
    static let limit = 10

    let id: UUID
    let toolName: String
    let toolInput: JSONValue?
    let title: String
    let detail: String?
    let startedAt: Date
    var isComplete: Bool
    var didFail: Bool

    init(event: HookEvent, at timestamp: Date, isComplete: Bool, didFail: Bool = false) {
        id = UUID()
        toolName = event.toolName ?? "Tool"
        toolInput = event.toolInput
        title = event.activityDescription ?? toolName
        detail = Self.detail(for: event.toolName ?? "", input: event.toolInput)
        startedAt = timestamp
        self.isComplete = isComplete
        self.didFail = didFail
    }

    func matches(_ event: HookEvent) -> Bool {
        event.toolName == toolName && event.toolInput == toolInput
    }

    var systemImage: String {
        switch toolName {
        case "Read": "doc.text"
        case "Edit", "MultiEdit", "NotebookEdit": "pencil"
        case "Write": "doc.badge.plus"
        case "Bash": "terminal"
        case "Grep", "Glob": "magnifyingglass"
        case "WebFetch", "WebSearch": "globe"
        case "Task", "Agent": "person.2"
        case "ExitPlanMode": "list.bullet.clipboard"
        default: "wrench"
        }
    }

    static func detail(for toolName: String, input: JSONValue?) -> String? {
        func lines(_ key: String, in value: JSONValue?) -> Int? {
            value?[key]?.stringValue.map(lineCount)
        }
        switch toolName {
        case "Edit":
            guard let added = lines("new_string", in: input), let removed = lines("old_string", in: input) else { return nil }
            return "+\(added) −\(removed)"
        case "MultiEdit":
            let edits = input?["edits"]?.arrayValue ?? []
            let added = edits.compactMap { lines("new_string", in: $0) }.reduce(0, +)
            let removed = edits.compactMap { lines("old_string", in: $0) }.reduce(0, +)
            return edits.isEmpty ? nil : "+\(added) −\(removed)"
        case "Write":
            return lines("content", in: input).map { "\($0) lines" }
        case "Read":
            guard let offset = lineNumber(input?["offset"] ?? .number(1)) else { return nil }
            if let limit = lineNumber(input?["limit"]) {
                return "lines \(offset)–\(offset + limit - 1)"
            }
            return offset > 1 ? "from line \(offset)" : nil
        case "Grep", "Glob":
            return input?["path"]?.stringValue.map { ($0 as NSString).lastPathComponent }
        default:
            return nil
        }
    }

    private static func lineNumber(_ value: JSONValue?) -> Int? {
        guard case .number(let number)? = value, (0...Double(Int32.max)).contains(number) else { return nil }
        return Int(number)
    }

    static func lineCount(_ text: String) -> Int {
        text.isEmpty ? 0 : text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
    }
}
