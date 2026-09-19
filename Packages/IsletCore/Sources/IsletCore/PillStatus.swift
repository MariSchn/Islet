import Foundation

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

    public init(text: String, systemImage: String? = nil, priority: Priority = .info) {
        self.text = text
        self.systemImage = systemImage
        self.priority = priority
    }
}
