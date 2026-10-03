import Foundation

public enum PillSelection: String, Sendable, Codable, CaseIterable, Identifiable {
    case lastViewed
    case latestActivity
    case mostImportant

    public static let `default` = PillSelection.lastViewed

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .lastViewed: String(localized: "Last viewed plugin", bundle: .module)
        case .latestActivity: String(localized: "Latest activity", bundle: .module)
        case .mostImportant: String(localized: "Most important", bundle: .module)
        }
    }

    public var summary: String {
        switch self {
        case .lastViewed: String(localized: "Shows the plugin that was open when the notch collapsed. If it has nothing to show, the most important activity is shown instead and stays until it ends.", bundle: .module)
        case .latestActivity: String(localized: "Shows whatever started most recently, for example music that just started playing or an agent that just started working.", bundle: .module)
        case .mostImportant: String(localized: "Shows the plugin with the most important activity, so a working agent is shown before music.", bundle: .module)
        }
    }
}
