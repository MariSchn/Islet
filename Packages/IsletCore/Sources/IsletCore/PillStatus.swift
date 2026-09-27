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

    public struct Ring: Sendable, Equatable {
        public struct Segment: Sendable, Equatable {
            public var value: Double
            public var tint: Color.Resolved

            public init(value: Double, tint: Color.Resolved) {
                self.value = value
                self.tint = tint
            }
        }

        public var segments: [Segment]

        public init(segments: [Segment]) {
            self.segments = segments
        }
    }

    public var text: String
    public var systemImage: String?
    public var priority: Priority
    public var artwork: CGImage?
    public var ring: Ring?
    public var tint: Color.Resolved?

    public init(text: String, systemImage: String? = nil, priority: Priority = .info, artwork: CGImage? = nil, ring: Ring? = nil, tint: Color.Resolved? = nil) {
        self.text = text
        self.systemImage = systemImage
        self.priority = priority
        self.artwork = artwork
        self.ring = ring
        self.tint = tint
    }
}

public struct PillAnnouncement: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var text: String
    public var systemImage: String?
    public var tint: Color.Resolved?
    public var priority: PillStatus.Priority

    public init(id: UUID = UUID(), text: String, systemImage: String? = nil, tint: Color.Resolved? = nil, priority: PillStatus.Priority = .info) {
        self.id = id
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
        self.priority = priority
    }
}
