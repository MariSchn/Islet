import CoreGraphics
import Foundation

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
        case .small: String(localized: "Small", bundle: .module)
        case .medium: String(localized: "Default", bundle: .module)
        case .large: String(localized: "Large", bundle: .module)
        case .extraLarge: String(localized: "Extra Large", bundle: .module)
        }
    }
}
