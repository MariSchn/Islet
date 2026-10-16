import Foundation
import Observation

public protocol PluginSettingsValue {}

extension Bool: PluginSettingsValue {}
extension Int: PluginSettingsValue {}
extension Double: PluginSettingsValue {}
extension String: PluginSettingsValue {}
extension Date: PluginSettingsValue {}
extension Data: PluginSettingsValue {}
extension Array: PluginSettingsValue where Element: PluginSettingsValue {}
extension Dictionary: PluginSettingsValue where Key == String, Value: PluginSettingsValue {}

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

    public func set(_ value: (some PluginSettingsValue)?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: prefix + key)
        } else {
            defaults.removeObject(forKey: prefix + key)
        }
        version += 1
    }
}
