import Foundation

public struct AgentSession: Identifiable, Sendable, Equatable {
    public enum Agent: String, Sendable, CaseIterable {
        case claudeCode = "claude-code"
        case codex

        public var displayName: String {
            switch self {
            case .claudeCode: "Claude Code"
            case .codex: "Codex"
            }
        }
    }

    public enum State: Sendable, Equatable {
        case starting
        case working
        case needsAttention(String)
        case done

        public var requiresAttention: Bool {
            if case .needsAttention = self { return true }
            return false
        }
    }

    public let id: String
    public var agent: Agent
    public var host: String?
    public var isRemote = false
    public var isUnreachable = false
    public var terminal: TerminalApp?
    public var tty: String?
    public var cwd: String?
    public var title: String?
    public var task: String?
    public var activity: String?
    public var state: State
    public var pendingRequests: [PendingRequest] = []
    public var activities: [ActivityEntry] = []
    public var plan: String?
    public var startedAt: Date
    public var turnStartedAt: Date
    public var updatedAt: Date

    public var pendingRequest: PendingRequest? { pendingRequests.first }

    public var projectName: String {
        guard let cwd, !cwd.isEmpty else { return agent.displayName }
        return (cwd as NSString).lastPathComponent
    }
}
