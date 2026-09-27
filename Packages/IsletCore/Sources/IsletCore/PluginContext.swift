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
    public var contentSize: CGSize?
    public private(set) var announcement: PillAnnouncement?

    init(manifest: PluginManifest, storageDirectory: URL, settings: PluginSettings) {
        self.manifest = manifest
        self.storageDirectory = storageDirectory
        self.settings = settings
    }

    public func announce(_ announcement: PillAnnouncement) {
        self.announcement = announcement
    }

    func clearAnnouncement() {
        announcement = nil
    }
}
