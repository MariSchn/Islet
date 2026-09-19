import Foundation

public struct AgentSession: Identifiable, Sendable, Equatable {
    public enum Agent: String, Sendable {
        case claudeCode

        public var displayName: String {
            switch self {
            case .claudeCode: "Claude Code"
            }
        }
    }

    public enum State: Sendable, Equatable {
        case starting
        case working
        case needsAttention(String)
        case done

        public var needsAttention: Bool {
            if case .needsAttention = self { return true }
            return false
        }
    }

    public let id: String
    public var agent: Agent
    public var host: String?
    public var cwd: String?
    public var task: String?
    public var activity: String?
    public var state: State
    public var startedAt: Date
    public var updatedAt: Date

    public var projectName: String {
        guard let cwd, !cwd.isEmpty else { return agent.displayName }
        return (cwd as NSString).lastPathComponent
    }
}
