import Foundation

struct AgentSession: Identifiable, Sendable, Equatable, Codable {
    enum Agent: String, Sendable, CaseIterable, Codable {
        case claudeCode = "claude-code"
        case codex
        case antigravity

        var displayName: String {
            switch self {
            case .claudeCode: "Claude Code"
            case .codex: "Codex"
            case .antigravity: "Antigravity"
            }
        }
    }

    enum State: Sendable, Equatable, Codable {
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
    var tmux: TmuxLocation?
    var transcriptPath: String?
    var cwd: String?
    var title: String?
    var hasStatusLineTitle = false
    var hasStatusLineModel = false
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

    enum CodingKeys: String, CodingKey {
        case id, agent, host, isRemote, isUnreachable, terminal, tty, pid, tmux, transcriptPath, cwd, title, hasStatusLineTitle
        case task, activity, state, activities, plan, details, startedAt, turnStartedAt, updatedAt
    }

    var pendingRequest: PendingRequest? { pendingRequests.first }

    var displayName: String {
        title ?? projectName
    }

    var projectName: String {
        guard let cwd, !cwd.isEmpty else { return agent.displayName }
        return (cwd as NSString).lastPathComponent
    }
}

struct SessionDetails: Sendable, Equatable, Codable {
    struct PullRequest: Sendable, Equatable, Codable {
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
    var branch: String?
    var pullRequest: PullRequest?
    var costUSD: Double?
    var linesAdded: Int?
    var linesRemoved: Int?
    var duration: Duration?

    var sessionSummary: String? {
        guard let costUSD else { return nil }
        var parts = [Self.currency(costUSD)]
        if linesAdded != nil || linesRemoved != nil {
            parts.append("+\(linesAdded ?? 0) −\(linesRemoved ?? 0)")
        }
        if let duration {
            parts.append(duration.formatted(.units(allowed: [.hours, .minutes])))
        }
        return parts.joined(separator: " · ")
    }

    static func currency(_ amount: Double) -> String {
        String(format: "$%.2f", locale: Locale(identifier: "en_US_POSIX"), amount)
    }

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
            branch: update.branch ?? branch,
            pullRequest: update.pullRequest,
            costUSD: update.costUSD ?? costUSD,
            linesAdded: update.linesAdded ?? linesAdded,
            linesRemoved: update.linesRemoved ?? linesRemoved,
            duration: update.duration ?? duration
        )
    }

    static let effortLevels: Set<String> = ["minimal", "low", "medium", "high", "xhigh", "max"]

    static func modelName(_ name: String, without effort: String?) -> String {
        guard let effort, name.lowercased().hasSuffix(" (\(effort.lowercased()))") else { return name }
        return String(name.dropLast(effort.count + 3))
    }

    static func antigravityModel(id: String) -> (model: String, effort: String?)? {
        var parts = id.split(separator: "-").map(String.init)
        guard parts.count > 1 else { return nil }
        let effort = Self.effortLevels.contains(parts[parts.count - 1].lowercased()) ? parts.removeLast() : nil
        let model = parts.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        return (model, effort)
    }

    static func percentText(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
}
