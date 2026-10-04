import Foundation

struct HookEvent: Sendable, Equatable, Decodable {
    enum Kind: String, Sendable, Decodable {
        case sessionStart = "SessionStart"
        case sessionEnd = "SessionEnd"
        case userPromptSubmit = "UserPromptSubmit"
        case preToolUse = "PreToolUse"
        case postToolUse = "PostToolUse"
        case postToolUseFailure = "PostToolUseFailure"
        case permissionRequest = "PermissionRequest"
        case permissionDenied = "PermissionDenied"
        case notification = "Notification"
        case stop = "Stop"
        case stopFailure = "StopFailure"
        case other

        init(from decoder: any Decoder) throws {
            self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .other
        }
    }

    var kind: Kind
    var sessionID: String
    var cwd: String?
    var transcriptPath: String?
    var model: String?
    var toolName: String?
    var toolInput: JSONValue?
    var prompt: String?
    var message: String?
    var notificationType: String?
    var source: String?
    var permissionMode: String?
    var agentType: String?
    var error: String?
    var lastAssistantMessage: String?
    var reason: String?
    var permissionSuggestions: [JSONValue]?
    var agent: AgentSession.Agent = .claudeCode
    var host: String?
    var terminal: TerminalApp?
    var tty: String?
    var pid: Int32?
    var tmux: TmuxLocation?
    var title: String?
    var effort: String?
    var branch: String?

    private enum CodingKeys: String, CodingKey {
        case kind = "hook_event_name"
        case sessionID = "session_id"
        case cwd
        case transcriptPath = "transcript_path"
        case model
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case prompt
        case message
        case notificationType = "notification_type"
        case source
        case permissionMode = "permission_mode"
        case agentType = "agent_type"
        case error
        case lastAssistantMessage = "last_assistant_message"
        case reason
        case permissionSuggestions = "permission_suggestions"
        case title = "session_title"
    }

    init(kind: Kind, sessionID: String, cwd: String? = nil, transcriptPath: String? = nil, toolName: String? = nil, toolInput: JSONValue? = nil, prompt: String? = nil, message: String? = nil, notificationType: String? = nil, source: String? = nil, permissionMode: String? = nil, agentType: String? = nil, error: String? = nil, lastAssistantMessage: String? = nil, reason: String? = nil, permissionSuggestions: [JSONValue]? = nil, agent: AgentSession.Agent = .claudeCode, host: String? = nil, terminal: TerminalApp? = nil, tty: String? = nil, pid: Int32? = nil, tmux: TmuxLocation? = nil, title: String? = nil) {
        self.kind = kind
        self.sessionID = sessionID
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.toolName = toolName
        self.toolInput = toolInput
        self.prompt = prompt
        self.message = message
        self.notificationType = notificationType
        self.source = source
        self.permissionMode = permissionMode
        self.agentType = agentType
        self.error = error
        self.lastAssistantMessage = lastAssistantMessage
        self.reason = reason
        self.permissionSuggestions = permissionSuggestions
        self.agent = agent
        self.host = host
        self.terminal = terminal
        self.tty = tty
        self.pid = pid
        self.tmux = tmux
        self.title = title
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        transcriptPath = try container.decodeIfPresent(String.self, forKey: .transcriptPath)
        model = try? container.decodeIfPresent(String.self, forKey: .model)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        toolInput = try container.decodeIfPresent(JSONValue.self, forKey: .toolInput)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        notificationType = try container.decodeIfPresent(String.self, forKey: .notificationType)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        permissionMode = try container.decodeIfPresent(String.self, forKey: .permissionMode)
        agentType = try container.decodeIfPresent(String.self, forKey: .agentType)
        error = try? container.decodeIfPresent(String.self, forKey: .error)
        lastAssistantMessage = try? container.decodeIfPresent(String.self, forKey: .lastAssistantMessage)
        reason = try? container.decodeIfPresent(String.self, forKey: .reason)
        permissionSuggestions = try? container.decode([JSONValue].self, forKey: .permissionSuggestions)
        title = (try? container.decodeIfPresent(String.self, forKey: .title)).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func decode(_ data: Data, agent: String? = nil, eventName: String? = nil, host: String? = nil, terminal: String? = nil, tty: String? = nil, pid: String? = nil, tmux: String? = nil, tmuxPane: String? = nil, title: String? = nil, branch: String? = nil, lastPrompt: (String) -> String? = TranscriptReader.lastAntigravityPrompt(at:), parent: (String) -> String? = TranscriptReader.antigravityParent(at:)) throws -> HookEvent {
        let agent = agent.flatMap(AgentSession.Agent.init(rawValue:)) ?? .claudeCode
        var event = switch agent {
        case .antigravity: try JSONDecoder().decode(AntigravityPayload.self, from: data).event(named: eventName ?? "", lastPrompt: lastPrompt, parent: parent)
        case .claudeCode, .codex: try JSONDecoder().decode(HookEvent.self, from: data)
        }
        event.agent = agent
        event.host = host
        event.terminal = terminal.flatMap { Self.isSafeIdentifier($0) ? TerminalApp(identifier: $0) : nil }
        event.tty = tty.flatMap { $0.hasPrefix("/dev/") && Self.isSafeIdentifier($0) ? $0 : nil }
        event.pid = pid.flatMap { Int32($0) }.flatMap { $0 > 1 ? $0 : nil }
        if let tmux, let tmuxPane { event.tmux = TmuxLocation(environment: tmux, pane: tmuxPane) }
        event.title = title.flatMap { $0.isEmpty ? nil : $0 } ?? event.title
        event.branch = branch.flatMap { $0.isEmpty ? nil : $0 }
        return event
    }

    private static let identifierCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-/"))

    static func isSafeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { identifierCharacters.contains($0) }
    }

    var isInAutoMode: Bool {
        permissionMode == "auto"
    }

    var failureDescription: String {
        switch error {
        case "rate_limit": "Rate limit reached"
        case "overloaded": "The API is overloaded"
        case "authentication_failed", "oauth_org_not_allowed": "Not logged in"
        case "account_on_hold", "billing_error": "Billing problem"
        case "max_output_tokens": "Response hit the output limit"
        case "model_not_found": "Model not available"
        default: lastAssistantMessage.flatMap { $0.isEmpty ? nil : $0 } ?? "The request failed"
        }
    }

    var isTaskNotification: Bool {
        prompt?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<task-notification>") == true
    }

    var activityDescription: String? {
        toolDescription.map { description in agentType.map { "\($0): \(description)" } ?? description }
    }

    private var toolDescription: String? {
        guard let toolName else { return nil }
        let input = toolInput
        func file(_ key: String) -> String? {
            input?[key]?.stringValue.map { ($0 as NSString).lastPathComponent }
        }
        let command = Self.command(in: input)
        switch toolName {
        case "Read": return file("file_path").map { "Read \($0)" } ?? "Read"
        case "Edit", "MultiEdit": return file("file_path").map { "Edit \($0)" } ?? "Edit"
        case "Write": return file("file_path").map { "Write \($0)" } ?? "Write"
        case "NotebookEdit": return file("notebook_path").map { "Edit \($0)" } ?? "Edit notebook"
        case "Bash", "shell", "exec_command": return input?["description"]?.stringValue ?? command.map { "$ \($0)" } ?? "Run command"
        case "apply_patch": return "Apply patch"
        case "Grep": return input?["pattern"]?.stringValue.map { "Search \($0)" } ?? "Search"
        case "Glob": return input?["pattern"]?.stringValue.map { "Find \($0)" } ?? "Find files"
        case "WebFetch": return input?["url"]?.stringValue.map { "Fetch \($0)" } ?? "Fetch"
        case "WebSearch": return input?["query"]?.stringValue.map { "Search web: \($0)" } ?? "Search web"
        case "Task", "Agent": return input?["description"]?.stringValue.map { "Agent: \($0)" } ?? "Run agent"
        default: return input?["toolSummary"]?.stringValue ?? toolName
        }
    }

    static func command(in input: JSONValue?) -> String? {
        guard let value = input?["command"] else { return nil }
        if let string = value.stringValue { return string }
        return value.arrayValue?.compactMap(\.stringValue).joined(separator: " ")
    }
}

struct AntigravityPayload: Decodable {
    struct ToolCall: Decodable {
        var name: String?
        var args: JSONValue?
    }

    var conversationId: String
    var workspacePaths: [String]?
    var transcriptPath: String?
    var toolCall: ToolCall?
    var error: String?
    var invocationNum: Int?
    var modelName: String?

    func event(named name: String, lastPrompt: (String) -> String?, parent: (String) -> String?) -> HookEvent {
        let failure = error.flatMap { $0.isEmpty ? nil : $0 }
        if let parent = transcriptPath.flatMap(parent) {
            return HookEvent(
                kind: name == "PostToolUse" ? (failure == nil ? .postToolUse : .postToolUseFailure) : .other,
                sessionID: parent,
                cwd: workspacePaths?.first,
                toolName: toolCall?.name,
                toolInput: toolCall?.args,
                agentType: "Subagent",
                agent: .antigravity
            )
        }
        let kind: HookEvent.Kind = switch name {
        case "PreInvocation": invocationNum ?? 0 == 0 ? .userPromptSubmit : .other
        case "PostToolUse": failure == nil ? .postToolUse : .postToolUseFailure
        case "Stop": failure == nil ? .stop : .stopFailure
        default: .other
        }
        var event = HookEvent(
            kind: kind,
            sessionID: conversationId,
            cwd: workspacePaths?.first,
            transcriptPath: transcriptPath,
            toolName: toolCall?.name,
            toolInput: toolCall?.args,
            prompt: kind == .userPromptSubmit ? transcriptPath.flatMap(lastPrompt) : nil,
            lastAssistantMessage: kind == .stopFailure ? failure : nil,
            agent: .antigravity
        )
        if let model = modelName.flatMap(SessionDetails.antigravityModel(id:)) {
            event.model = model.model
            event.effort = model.effort
        }
        return event
    }
}
