import Foundation

struct AgentSession: Identifiable, Sendable, Equatable {
    enum Agent: String, Sendable, CaseIterable {
        case claudeCode = "claude-code"
        case codex

        var displayName: String {
            switch self {
            case .claudeCode: "Claude Code"
            case .codex: "Codex"
            }
        }
    }

    enum State: Sendable, Equatable {
        case starting
        case working
        case needsAttention(String)
        case done
        case interrupted
        case failed(String)

        var requiresAttention: Bool {
            switch self {
            case .needsAttention, .failed: true
            case .starting, .working, .done, .interrupted: false
            }
        }
    }

    let id: String
    var agent: Agent
    var host: String?
    var isRemote = false
    var isUnreachable = false
    var terminal: TerminalApp?
    var tty: String?
    var pid: Int32?
    var transcriptPath: String?
    var cwd: String?
    var title: String?
    var task: String?
    var activity: String?
    var state: State
    var pendingRequests: [PendingRequest] = []
    var activities: [ActivityEntry] = []
    var plan: String?
    var startedAt: Date
    var turnStartedAt: Date
    var updatedAt: Date

    var pendingRequest: PendingRequest? { pendingRequests.first }

    var displayName: String {
        title ?? projectName
    }

    var projectName: String {
        guard let cwd, !cwd.isEmpty else { return agent.displayName }
        return (cwd as NSString).lastPathComponent
    }
}
