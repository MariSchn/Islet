import Foundation
import Observation

@MainActor
@Observable
public final class PluginSettings {
    private let defaults: UserDefaults
    private let prefix: String
    private var version = 0

    init(pluginID: String, defaults: UserDefaults) {
        self.defaults = defaults
        self.prefix = "plugin.\(pluginID)."
    }

    public func value<T>(forKey key: String) -> T? {
        _ = version
        return defaults.object(forKey: prefix + key) as? T
    }

    public func set(_ value: (some Any)?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: prefix + key)
        } else {
            defaults.removeObject(forKey: prefix + key)
        }
        version += 1
    }
}
