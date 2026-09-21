import AppKit

public struct NotchDisplay: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let hasHardwareNotch: Bool
    public let isPrimary: Bool

    public init(id: String, name: String, hasHardwareNotch: Bool, isPrimary: Bool) {
        self.id = id
        self.name = name
        self.hasHardwareNotch = hasHardwareNotch
        self.isPrimary = isPrimary
    }

    public init(screen: NSScreen) {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        self.init(
            id: number.map { String($0.uint32Value) } ?? screen.localizedName,
            name: screen.localizedName,
            hasHardwareNotch: screen.safeAreaInsets.top > 0,
            isPrimary: screen == NSScreen.screens.first
        )
    }

    public static func connected() -> [NotchDisplay] {
        NSScreen.screens.map(NotchDisplay.init(screen:))
    }
}

public enum NotchDisplayPlacement: Sendable, Hashable, Codable {
    case builtIn
    case primary
    case all
    case named(String)

    public static let `default` = NotchDisplayPlacement.builtIn

    public var displayName: String {
        switch self {
        case .builtIn: "Built-in display"
        case .primary: "Primary display"
        case .all: "All displays"
        case .named(let name): name
        }
    }

    public func displays(among connected: [NotchDisplay]) -> [NotchDisplay] {
        guard !connected.isEmpty else { return [] }
        let fallback = connected.first { $0.hasHardwareNotch } ?? connected.first { $0.isPrimary } ?? connected[0]
        switch self {
        case .builtIn:
            return [fallback]
        case .primary:
            return [connected.first { $0.isPrimary } ?? fallback]
        case .all:
            return connected
        case .named(let name):
            return [connected.first { $0.name == name } ?? fallback]
        }
    }
}
