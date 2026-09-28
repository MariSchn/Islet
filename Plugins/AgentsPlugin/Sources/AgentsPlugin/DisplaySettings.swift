struct DisplaySettings: Sendable, Equatable {
    enum PillContent: String, Sendable, CaseIterable, Identifiable {
        case ring
        case summary

        var id: Self { self }

        var displayName: String {
            switch self {
            case .ring: "Status ring"
            case .summary: "Summary text"
            }
        }
    }

    static let historyLengthRange = 1...ActivityEntry.limit

    var showsFiveHourLimit = true
    var showsWeeklyLimit = true
    var showsResetTimes = true
    var pillContent = PillContent.ring
    var pillShowsWorking = true
    var pillShowsFinished = true
    var ringKeepsFinishedSessions = true
    var historyLength = 8 {
        didSet { historyLength = min(max(historyLength, Self.historyLengthRange.lowerBound), Self.historyLengthRange.upperBound) }
    }

    init() {}

    func visibleUsage(_ usage: ClaudeUsage) -> ClaudeUsage? {
        let visible = ClaudeUsage(fiveHour: showsFiveHourLimit ? usage.fiveHour : nil, sevenDay: showsWeeklyLimit ? usage.sevenDay : nil)
        return visible.isEmpty ? nil : visible
    }
}
