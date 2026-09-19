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
}
