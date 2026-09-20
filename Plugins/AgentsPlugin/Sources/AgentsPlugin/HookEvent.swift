import Foundation

public struct HookEvent: Sendable, Equatable, Decodable {
    public enum Kind: String, Sendable, Decodable {
        case sessionStart = "SessionStart"
        case sessionEnd = "SessionEnd"
        case userPromptSubmit = "UserPromptSubmit"
        case preToolUse = "PreToolUse"
        case postToolUse = "PostToolUse"
        case permissionRequest = "PermissionRequest"
        case notification = "Notification"
        case stop = "Stop"
    }

    public var kind: Kind
    public var sessionID: String
    public var cwd: String?
    public var toolName: String?
    public var toolInput: JSONValue?
    public var prompt: String?
    public var message: String?
    public var notificationType: String?
    public var source: String?
    public var agent: AgentSession.Agent = .claudeCode
    public var host: String?
    public var terminal: TerminalApp?
    public var tty: String?

    private enum CodingKeys: String, CodingKey {
        case kind = "hook_event_name"
        case sessionID = "session_id"
        case cwd
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case prompt
        case message
        case notificationType = "notification_type"
        case source
    }

    public init(kind: Kind, sessionID: String, cwd: String? = nil, toolName: String? = nil, toolInput: JSONValue? = nil, prompt: String? = nil, message: String? = nil, notificationType: String? = nil, source: String? = nil, agent: AgentSession.Agent = .claudeCode, host: String? = nil, terminal: TerminalApp? = nil, tty: String? = nil) {
        self.kind = kind
        self.sessionID = sessionID
        self.cwd = cwd
        self.toolName = toolName
        self.toolInput = toolInput
        self.prompt = prompt
        self.message = message
        self.notificationType = notificationType
        self.source = source
        self.agent = agent
        self.host = host
        self.terminal = terminal
        self.tty = tty
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        toolInput = try container.decodeIfPresent(JSONValue.self, forKey: .toolInput)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        notificationType = try container.decodeIfPresent(String.self, forKey: .notificationType)
        source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    public static func decode(_ data: Data, agent: String? = nil, host: String? = nil, terminal: String? = nil, tty: String? = nil) throws -> HookEvent {
        var event = try JSONDecoder().decode(HookEvent.self, from: data)
        event.agent = agent.flatMap(AgentSession.Agent.init(rawValue:)) ?? .claudeCode
        event.host = host
        event.terminal = terminal.flatMap(TerminalApp.init)
        event.tty = tty.flatMap { $0.hasPrefix("/dev/") ? $0 : nil }
        return event
    }

    public var activityDescription: String? {
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
        default: return toolName
        }
    }

    static func command(in input: JSONValue?) -> String? {
        guard let value = input?["command"] else { return nil }
        if let string = value.stringValue { return string }
        return value.arrayValue?.compactMap(\.stringValue).joined(separator: " ")
    }
}
