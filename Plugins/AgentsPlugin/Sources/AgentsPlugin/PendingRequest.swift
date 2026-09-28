import Foundation

struct PendingRequest: Sendable, Equatable, Identifiable {
    struct Question: Sendable, Equatable {
        struct Option: Sendable, Equatable {
            var label: String
            var description: String?

            init(label: String, description: String? = nil) {
                self.label = label
                self.description = description
            }
        }

        var text: String
        var header: String?
        var options: [Option]
        var multiSelect: Bool

        init(text: String, header: String? = nil, options: [Option], multiSelect: Bool = false) {
            self.text = text
            self.header = header
            self.options = options
            self.multiSelect = multiSelect
        }
    }

    enum Kind: Sendable, Equatable {
        case permission(tool: String, detail: String?)
        case question([Question])
    }

    let id: UUID
    let toolName: String
    let toolInput: JSONValue?
    let agentType: String?
    let kind: Kind

    init?(id: UUID = UUID(), toolName: String, toolInput: JSONValue?, agentType: String? = nil) {
        self.id = id
        self.toolName = toolName
        self.toolInput = toolInput
        self.agentType = agentType
        switch toolName {
        case "AskUserQuestion":
            guard let questions = Self.questions(from: toolInput), !questions.isEmpty else { return nil }
            kind = .question(questions)
        case "ExitPlanMode":
            return nil
        default:
            kind = .permission(tool: toolName, detail: Self.permissionDetail(tool: toolName, input: toolInput))
        }
    }

    var isQuestion: Bool {
        if case .question = kind { return true }
        return false
    }

    var activityDescription: String? {
        HookEvent(kind: .permissionRequest, sessionID: "", toolName: toolName, toolInput: toolInput).activityDescription
    }

    var title: String {
        switch kind {
        case .permission(let tool, _): "Allow \(tool)?"
        case .question(let questions): questions.count == 1 ? "Question" : "\(questions.count) questions"
        }
    }

    private static func questions(from input: JSONValue?) -> [Question]? {
        input?["questions"]?.arrayValue?.compactMap { item in
            guard let text = item["question"]?.stringValue else { return nil }
            let options = item["options"]?.arrayValue?.compactMap { option in
                option["label"]?.stringValue.map { Question.Option(label: $0, description: option["description"]?.stringValue) }
            } ?? []
            guard !options.isEmpty else { return nil }
            return Question(text: text, header: item["header"]?.stringValue, options: options, multiSelect: item["multiSelect"]?.boolValue ?? false)
        }
    }

    private static func permissionDetail(tool: String, input: JSONValue?) -> String? {
        switch tool {
        case "Bash", "shell", "exec_command": HookEvent.command(in: input)
        case "Read", "Edit", "MultiEdit", "Write": input?["file_path"]?.stringValue
        case "NotebookEdit": input?["notebook_path"]?.stringValue
        case "WebFetch": input?["url"]?.stringValue
        case "WebSearch": input?["query"]?.stringValue
        case "Task", "Agent": input?["description"]?.stringValue
        default: nil
        }
    }
}

enum PermissionDecision: Sendable, Equatable {
    case allow
    case deny
    case answers([String: String])

    func reply(for request: PendingRequest) -> HookReply {
        var decision: [String: JSONValue]
        switch self {
        case .allow:
            decision = ["behavior": .string("allow")]
        case .deny:
            decision = ["behavior": .string("deny"), "message": .string("The user denied this request in Islet.")]
        case .answers(let answers):
            var input: [String: JSONValue] = [:]
            if case .object(let object)? = request.toolInput { input = object }
            input["answers"] = .object(answers.mapValues { JSONValue.string($0) })
            decision = ["behavior": .string("allow"), "updatedInput": .object(input)]
        }
        let output: JSONValue = .object([
            "hookSpecificOutput": .object([
                "hookEventName": .string("PermissionRequest"),
                "decision": .object(decision),
            ]),
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(output)) ?? Data("{}".utf8)
        return HookReply(body: String(decoding: data, as: UTF8.self))
    }
}
