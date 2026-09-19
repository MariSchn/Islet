import Foundation

public struct PluginManifest: Sendable, Hashable {
    public let id: String
    public let displayName: String
    public let systemImage: String

    public init(id: String, displayName: String, systemImage: String) {
        self.id = id
        self.displayName = displayName
        self.systemImage = systemImage
    }

    public var hasValidID: Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return !id.isEmpty
            && id.unicodeScalars.allSatisfy(allowed.contains)
            && !id.hasPrefix(".")
            && !id.contains("..")
    }
}
