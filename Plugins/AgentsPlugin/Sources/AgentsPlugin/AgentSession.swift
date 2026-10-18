import Foundation

struct AgentSession: Identifiable, Sendable, Equatable, Codable {
    enum Agent: String, Sendable, CaseIterable, Codable {
        case claudeCode = "claude-code"
        case codex
        case antigravity
        case cursor

        var displayName: String {
            switch self {
            case .claudeCode: "Claude Code"
            case .codex: "Codex"
            case .antigravity: "Antigravity"
            case .cursor: "Cursor"
            }
        }

        var hookPath: String {
            switch self {
            case .claudeCode: ".claude"
            case .codex: ".codex"
            case .antigravity: ".gemini/config"
            case .cursor: ".cursor"
            }
        }

        var statusLinePath: String? {
            switch self {
            case .claudeCode: ".claude"
            case .codex, .cursor: nil
            case .antigravity: ".gemini/antigravity-cli"
            }
        }

        var installationPath: String? {
            switch self {
            case .claudeCode: nil
            case .codex: ".codex"
            case .antigravity: ".gemini/antigravity-cli"
            case .cursor: ".cursor"
            }
        }
    }

    enum State: Sendable, Equatable, Codable {
        case starting
        case working
        case needsAttention(String)
        case waiting
        case done
        case interrupted
        case failed(String)

        var isFailed: Bool {
            if case .failed = self { return true }
            return false
        }

        var requiresAttention: Bool {
            switch self {
            case .needsAttention, .failed: true
            case .starting, .working, .waiting, .done, .interrupted: false
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
    var model: String?
    var cwd: String?
    var title: String?
    var hasStatusLineTitle = false
    var hasStatusLineModel = false
    var task: String?
    var activity: String?
    var state: State
    var pendingRequests: [PendingRequest] = []
    var requestsInTerminal: [TerminalRequest] = []
    var backgroundTasks: [BackgroundTask] = []
    var activities: [ActivityEntry] = []
    var plan: String?
    var details = SessionDetails()
    var startedAt: Date
    var turnStartedAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, agent, host, isRemote, isUnreachable, terminal, tty, pid, tmux, transcriptPath, model, cwd, title, hasStatusLineTitle, hasStatusLineModel
        case task, activity, state, backgroundTasks, activities, plan, details, startedAt, turnStartedAt, updatedAt
    }

    var pendingRequest: PendingRequest? { pendingRequests.first }

    mutating func completeOpenActivities() {
        for index in activities.indices where !activities[index].isComplete {
            activities[index].isComplete = true
        }
    }

    var displayName: String {
        title ?? projectName
    }

    var isGeminiModel: Bool {
        (details.model ?? model)?.localizedCaseInsensitiveContains("gemini") == true
    }

    var projectName: String {
        guard let cwd, !cwd.isEmpty else { return agent.displayName }
        return (cwd as NSString).lastPathComponent
    }
}

struct TerminalRequest: Sendable, Equatable {
    var toolName: String
    var toolInput: JSONValue?
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

    static func claudeModelName(id: String) -> String {
        guard let start = id.range(of: "claude-") else { return id }
        let parts = id[start.upperBound...].prefix { $0 != "[" && $0 != "@" }.split(separator: "-").map(String.init)
        guard let family = parts.firstIndex(where: { Int($0) == nil }) else { return id }
        let version = parts.filter { Int($0) != nil && $0.count < 8 }.joined(separator: ".")
        return parts[family].capitalized + (version.isEmpty ? "" : " \(version)")
    }

    static func percentText(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
}

extension AgentSession {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        agent = try container.decode(Agent.self, forKey: .agent)
        host = try container.decodeIfPresent(String.self, forKey: .host)
        isRemote = try container.decodeIfPresent(Bool.self, forKey: .isRemote) ?? false
        isUnreachable = try container.decodeIfPresent(Bool.self, forKey: .isUnreachable) ?? false
        terminal = try container.decodeIfPresent(TerminalApp.self, forKey: .terminal)
        tty = try container.decodeIfPresent(String.self, forKey: .tty)
        pid = try container.decodeIfPresent(Int32.self, forKey: .pid)
        tmux = try container.decodeIfPresent(TmuxLocation.self, forKey: .tmux)
        transcriptPath = try container.decodeIfPresent(String.self, forKey: .transcriptPath)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        hasStatusLineTitle = try container.decodeIfPresent(Bool.self, forKey: .hasStatusLineTitle) ?? false
        hasStatusLineModel = try container.decodeIfPresent(Bool.self, forKey: .hasStatusLineModel) ?? false
        task = try container.decodeIfPresent(String.self, forKey: .task)
        activity = try container.decodeIfPresent(String.self, forKey: .activity)
        state = try container.decode(State.self, forKey: .state)
        backgroundTasks = try container.decodeIfPresent([BackgroundTask].self, forKey: .backgroundTasks) ?? []
        activities = try container.decodeIfPresent([ActivityEntry].self, forKey: .activities) ?? []
        plan = try container.decodeIfPresent(String.self, forKey: .plan)
        details = try container.decodeIfPresent(SessionDetails.self, forKey: .details) ?? SessionDetails()
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        turnStartedAt = try container.decode(Date.self, forKey: .turnStartedAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
