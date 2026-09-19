import Foundation
import Observation

@MainActor
@Observable
public final class AppSettings {
    public var animation: NotchAnimation {
        didSet { save(animation, forKey: Keys.animation) }
    }
    public var switchesToDropTargetOnDrag: Bool {
        didSet { save(switchesToDropTargetOnDrag, forKey: Keys.switchesToDropTargetOnDrag) }
    }
    public var showsIdleNotchOutline: Bool {
        didSet { save(showsIdleNotchOutline, forKey: Keys.showsIdleNotchOutline) }
    }

    private let defaults: UserDefaults?

    private enum Keys {
        static let animation = "islet.settings.animation"
        static let switchesToDropTargetOnDrag = "islet.settings.switchesToDropTargetOnDrag"
        static let showsIdleNotchOutline = "islet.settings.showsIdleNotchOutline"
    }

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        animation = Self.load(NotchAnimation.self, forKey: Keys.animation, from: defaults) ?? .default
        switchesToDropTargetOnDrag = Self.load(Bool.self, forKey: Keys.switchesToDropTargetOnDrag, from: defaults) ?? true
        showsIdleNotchOutline = Self.load(Bool.self, forKey: Keys.showsIdleNotchOutline, from: defaults) ?? false
    }

    public func resetAnimation() {
        animation = .default
    }

    private static func load<T: Decodable>(_ type: T.Type, forKey key: String, from defaults: UserDefaults?) -> T? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save(_ value: some Encodable, forKey key: String) {
        guard let defaults, let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
