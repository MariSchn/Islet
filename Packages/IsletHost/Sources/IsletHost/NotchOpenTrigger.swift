public enum NotchOpenTrigger: String, Sendable, Codable, CaseIterable, Identifiable {
    case hover
    case click

    public static let `default` = NotchOpenTrigger.hover

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .hover: "Hover"
        case .click: "Click"
        }
    }
}
