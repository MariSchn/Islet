public struct DisplaySettings: Sendable, Equatable {
    public enum PillContent: String, Sendable, CaseIterable, Identifiable {
        case ring
        case summary

        public var id: Self { self }

        public var displayName: String {
            switch self {
            case .ring: "Status ring"
            case .summary: "Summary text"
            }
        }
    }

    public static let historyLengthRange = 1...ActivityEntry.limit

    public var showsFiveHourLimit = true
    public var showsWeeklyLimit = true
    public var showsResetTimes = true
    public var pillContent = PillContent.ring
    public var pillShowsWorking = true
    public var pillShowsFinished = true
    public var historyLength = 8 {
        didSet { historyLength = min(max(historyLength, Self.historyLengthRange.lowerBound), Self.historyLengthRange.upperBound) }
    }

    public init() {}

    public func visibleUsage(_ usage: ClaudeUsage) -> ClaudeUsage? {
        let visible = ClaudeUsage(fiveHour: showsFiveHourLimit ? usage.fiveHour : nil, sevenDay: showsWeeklyLimit ? usage.sevenDay : nil)
        return visible.isEmpty ? nil : visible
    }
}
