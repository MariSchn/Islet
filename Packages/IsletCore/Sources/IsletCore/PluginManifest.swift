import SwiftUI

public struct PluginManifest: Sendable, Hashable {
    public let id: String
    public let displayName: String
    public let systemImage: String
    public let summary: String?
    public let tint: Color?

    public init(id: String, displayName: String, systemImage: String, summary: String? = nil, tint: Color? = nil) {
        self.id = id
        self.displayName = displayName
        self.systemImage = systemImage
        self.summary = summary
        self.tint = tint
    }

    public var hasValidID: Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return !id.isEmpty
            && id.unicodeScalars.allSatisfy(allowed.contains)
            && !id.hasPrefix(".")
            && !id.contains("..")
    }
}
