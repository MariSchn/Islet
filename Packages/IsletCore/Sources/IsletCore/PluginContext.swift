import Foundation
import Observation

@MainActor
@Observable
public final class PluginContext {
    public let manifest: PluginManifest
    public let storageDirectory: URL
    public let settings: UserDefaults
    public var pillStatus: PillStatus?

    public init(manifest: PluginManifest, storageDirectory: URL, settings: UserDefaults) {
        self.manifest = manifest
        self.storageDirectory = storageDirectory
        self.settings = settings
    }
}
