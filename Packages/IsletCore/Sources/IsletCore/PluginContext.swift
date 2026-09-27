import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
public final class PluginContext {
    public let manifest: PluginManifest
    public let storageDirectory: URL
    public let settings: PluginSettings
    public var pillStatus: PillStatus? {
        didSet {
            guard let pillStatus else { return }
            if let oldValue, oldValue.priority >= pillStatus.priority { return }
            Self.lastActivity += 1
            pillActivity = Self.lastActivity
        }
    }
    public var contentSize: CGSize?
    public private(set) var announcement: PillAnnouncement?
    private(set) var pillActivity = 0

    private static var lastActivity = 0

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
