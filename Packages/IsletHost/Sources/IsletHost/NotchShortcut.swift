public enum NotchShortcut: String, Sendable, Codable, CaseIterable, Identifiable {
    case off
    case controlOptionSpace
    case controlOptionN
    case controlCommandN
    case controlOptionI

    public static let `default` = NotchShortcut.off

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .controlOptionSpace: "⌃⌥Space"
        case .controlOptionN: "⌃⌥N"
        case .controlCommandN: "⌃⌘N"
        case .controlOptionI: "⌃⌥I"
        }
    }
}
