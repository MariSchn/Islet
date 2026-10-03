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
    var hasStatusLineTitle = false
    var task: String?
    var activity: String?
    var state: State
    var pendingRequests: [PendingRequest] = []
    var activities: [ActivityEntry] = []
    var plan: String?
    var details = SessionDetails()
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

struct SessionDetails: Sendable, Equatable {
    struct PullRequest: Sendable, Equatable {
        var number: Int
        var url: String?
        var reviewState: String?
        var isMergeRequest: Bool

        var label: String { isMergeRequest ? "!\(number)" : "#\(number)" }

        var reviewWords: String? {
            switch reviewState {
            case nil: nil
            case "changes_requested": "changes requested"
            case let state?: state.replacingOccurrences(of: "_", with: " ")
            }
        }

        var help: String {
            let kind = isMergeRequest ? "Merge request" : "Pull request"
            guard let reviewWords else { return "\(kind) \(label)" }
            return "\(kind) \(label): \(reviewWords)"
        }

        var announcementMark: String {
            isMergeRequest ? "MR \(label)" : "PR \(label)"
        }
    }

    var contextPercentage: Double?
    var model: String?
    var effort: String?
    var fastMode: Bool?
    var worktree: String?
    var pullRequest: PullRequest?

    var badgeText: String? {
        let parts = [model, effort, fastMode == true ? "fast" : nil].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    func merging(_ update: SessionDetails) -> SessionDetails {
        SessionDetails(
            contextPercentage: update.contextPercentage ?? contextPercentage,
            model: update.model ?? model,
            effort: update.effort ?? effort,
            fastMode: update.fastMode ?? fastMode,
            worktree: update.worktree,
            pullRequest: update.pullRequest
        )
    }

    static func percentText(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
}
