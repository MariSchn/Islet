import Foundation

public struct PluginSettings {
    private let defaults: UserDefaults
    private let prefix: String

    init(pluginID: String, defaults: UserDefaults) {
        self.defaults = defaults
        self.prefix = "plugin.\(pluginID)."
    }

    public func value<T>(forKey key: String) -> T? {
        defaults.object(forKey: prefix + key) as? T
    }

    public func set(_ value: (some Any)?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: prefix + key)
        } else {
            defaults.removeObject(forKey: prefix + key)
        }
    }
}
