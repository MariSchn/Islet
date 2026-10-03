import AppKit
import Foundation

public struct NotchDisplay: Sendable, Hashable, Identifiable {
    public let id: String
    public let persistentID: String
    public let name: String
    public let isBuiltIn: Bool
    public let hasHardwareNotch: Bool
    public let isPrimary: Bool

    public init(id: String, persistentID: String, name: String, isBuiltIn: Bool, hasHardwareNotch: Bool, isPrimary: Bool) {
        self.id = id
        self.persistentID = persistentID
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.hasHardwareNotch = hasHardwareNotch
        self.isPrimary = isPrimary
    }

    public init(screen: NSScreen) {
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
        let number = displayID.map { String($0) } ?? screen.localizedName
        let uuid = displayID.flatMap { CGDisplayCreateUUIDFromDisplayID($0)?.takeRetainedValue() }.flatMap { CFUUIDCreateString(nil, $0) as String? }
        self.init(
            id: number,
            persistentID: uuid ?? number,
            name: screen.localizedName,
            isBuiltIn: displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false,
            hasHardwareNotch: screen.safeAreaInsets.top > 0,
            isPrimary: screen == NSScreen.screens.first
        )
    }

    public static func connected() -> [NotchDisplay] {
        disambiguated(NSScreen.screens.map(NotchDisplay.init(screen:)))
    }

    static func disambiguated(_ displays: [NotchDisplay]) -> [NotchDisplay] {
        displays.map { display in
            guard displays.filter({ $0.persistentID == display.persistentID }).count > 1 else { return display }
            return NotchDisplay(
                id: display.id,
                persistentID: "\(display.persistentID)-\(display.id)",
                name: display.name,
                isBuiltIn: display.isBuiltIn,
                hasHardwareNotch: display.hasHardwareNotch,
                isPrimary: display.isPrimary
            )
        }
    }
}

public enum NotchDisplayPlacement: Sendable, Hashable, Codable {
    case builtIn
    case primary
    case all
    case display(id: String, name: String)

    public static let `default` = NotchDisplayPlacement.builtIn

    public var displayName: String {
        switch self {
        case .builtIn: String(localized: "Built-in display", bundle: .module)
        case .primary: String(localized: "Primary display", bundle: .module)
        case .all: String(localized: "All displays", bundle: .module)
        case .display(_, let name): name
        }
    }

    public func displays(among connected: [NotchDisplay]) -> [NotchDisplay] {
        guard !connected.isEmpty else { return [] }
        let fallback = connected.first { $0.isBuiltIn } ?? connected.first { $0.hasHardwareNotch } ?? connected.first { $0.isPrimary } ?? connected[0]
        switch self {
        case .builtIn:
            return [fallback]
        case .primary:
            return [connected.first { $0.isPrimary } ?? fallback]
        case .all:
            return connected
        case .display(let id, _):
            return [connected.first { $0.persistentID == id } ?? fallback]
        }
    }
}
