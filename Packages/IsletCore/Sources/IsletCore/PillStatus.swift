import Foundation

public struct PillTint: Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public struct PillStatus: Sendable, Equatable {
    public enum Priority: Int, Sendable, Comparable {
        case ambient
        case info
        case attention
        case urgent

        public static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public var text: String
    public var systemImage: String?
    public var priority: Priority
    public var artwork: Data?
    public var tint: PillTint?

    public init(text: String, systemImage: String? = nil, priority: Priority = .info, artwork: Data? = nil, tint: PillTint? = nil) {
        self.text = text
        self.systemImage = systemImage
        self.priority = priority
        self.artwork = artwork
        self.tint = tint
    }
}
