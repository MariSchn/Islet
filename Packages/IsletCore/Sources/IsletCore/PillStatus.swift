import CoreGraphics
import SwiftUI

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
    public var artwork: CGImage?
    public var tint: Color.Resolved?

    public init(text: String, systemImage: String? = nil, priority: Priority = .info, artwork: CGImage? = nil, tint: Color.Resolved? = nil) {
        self.text = text
        self.systemImage = systemImage
        self.priority = priority
        self.artwork = artwork
        self.tint = tint
    }
}
