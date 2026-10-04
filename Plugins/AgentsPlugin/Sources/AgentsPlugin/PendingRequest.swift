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
    let alwaysAllowRule: JSONValue?

    init?(id: UUID = UUID(), toolName: String, toolInput: JSONValue?, agentType: String? = nil, permissionSuggestions: [JSONValue]? = nil) {
        self.id = id
        self.toolName = toolName
        self.toolInput = toolInput
        self.agentType = agentType
        switch toolName {
        case _ where toolName == "AskUserQuestion" || Self.codexQuestionTools.contains(toolName):
            guard let questions = Self.questions(from: toolInput, requiresOptions: toolName == "AskUserQuestion"), !questions.isEmpty else { return nil }
            kind = .question(questions)
            alwaysAllowRule = nil
        case "ExitPlanMode":
            return nil
        default:
            kind = .permission(tool: toolName, detail: Self.permissionDetail(tool: toolName, input: toolInput))
            alwaysAllowRule = Self.alwaysAllowRule(in: permissionSuggestions)
        }
    }

    var alwaysAllowDescription: String? {
        guard let alwaysAllowRule else { return nil }
        let rules = alwaysAllowRule["rules"]?.arrayValue?.compactMap(Self.ruleDescription).joined(separator: ", ") ?? ""
        let saved = Self.destinationDescription(alwaysAllowRule["destination"]?.stringValue)
        switch (rules.isEmpty, saved) {
        case (false, let saved?): return "\(rules) \(saved)"
        case (false, nil): return rules
        case (true, let saved?): return saved
        case (true, nil): return nil
        }
    }

    private static func alwaysAllowRule(in suggestions: [JSONValue]?) -> JSONValue? {
        suggestions?.first { suggestion in
            suggestion["type"]?.stringValue == "addRules" && suggestion["behavior"]?.stringValue == "allow"
        }
    }

    private static func ruleDescription(_ rule: JSONValue) -> String? {
        guard let toolName = rule["toolName"]?.stringValue else { return nil }
        guard let content = rule["ruleContent"]?.stringValue, !content.isEmpty else { return toolName }
        return "\(toolName)(\(content))"
    }

    private static func destinationDescription(_ destination: String?) -> String? {
        switch destination {
        case "localSettings": "for this project, only you"
        case "projectSettings": "for this project"
        case "userSettings": "for all projects"
        case "session": "for this session"
        default: nil
        }
    }

    static let codexQuestionTools: Set = ["request_user_input", "request_user_input_async"]

    var isAnswerable: Bool {
        !Self.codexQuestionTools.contains(toolName)
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

    private static func questions(from input: JSONValue?, requiresOptions: Bool) -> [Question]? {
        input?["questions"]?.arrayValue?.compactMap { item in
            guard let text = item["question"]?.stringValue ?? item["title"]?.stringValue else { return nil }
            let options = item["options"]?.arrayValue?.compactMap { option in
                (option["label"]?.stringValue ?? option.stringValue).map { Question.Option(label: $0, description: option["description"]?.stringValue) }
            } ?? []
            guard !options.isEmpty || !requiresOptions else { return nil }
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
    case allowAlways
    case deny
    case answers([String: String])

    func reply(for request: PendingRequest) -> HookReply {
        var decision: [String: JSONValue]
        switch self {
        case .allow:
            decision = ["behavior": .string("allow")]
        case .allowAlways:
            decision = ["behavior": .string("allow")]
            if let rule = request.alwaysAllowRule {
                decision["updatedPermissions"] = .array([rule])
            }
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
