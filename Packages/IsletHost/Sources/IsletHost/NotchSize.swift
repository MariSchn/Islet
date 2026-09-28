import CoreGraphics

public enum NotchSize: String, Sendable, Codable, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case extraLarge

    public static let `default` = NotchSize.medium

    public var id: Self { self }

    public var scale: CGFloat {
        switch self {
        case .small: 0.85
        case .medium: 1
        case .large: 1.2
        case .extraLarge: 1.4
        }
    }

    public var displayName: String {
        switch self {
        case .small: "Small"
        case .medium: "Default"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }
}
