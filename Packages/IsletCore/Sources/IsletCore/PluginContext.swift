import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
public final class PluginContext {
    public let manifest: PluginManifest
    public let storageDirectory: URL
    public let settings: PluginSettings
    public var pillStatus: PillStatus?
    public var screenSize: CGSize?

    init(manifest: PluginManifest, storageDirectory: URL, settings: PluginSettings) {
        self.manifest = manifest
        self.storageDirectory = storageDirectory
        self.settings = settings
    }
}
