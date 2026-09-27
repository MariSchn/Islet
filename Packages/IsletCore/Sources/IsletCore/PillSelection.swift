public enum PillSelection: String, Sendable, Codable, CaseIterable, Identifiable {
    case lastViewed
    case latestActivity
    case mostImportant

    public static let `default` = PillSelection.lastViewed

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .lastViewed: "Last viewed plugin"
        case .latestActivity: "Latest activity"
        case .mostImportant: "Most important"
        }
    }

    public var summary: String {
        switch self {
        case .lastViewed: "Shows the plugin that was open when the notch collapsed. If it has nothing to show, the most important activity is shown instead and stays until it ends."
        case .latestActivity: "Shows whatever started most recently, for example music that just started playing or an agent that just started working."
        case .mostImportant: "Shows the plugin with the most important activity, so a working agent is shown before music."
        }
    }
}
