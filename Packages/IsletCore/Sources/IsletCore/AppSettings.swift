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
    public var drawsIdleNotchShape: Bool {
        didSet { save(drawsIdleNotchShape, forKey: Keys.drawsIdleNotchShape) }
    }
    public var notchSize: NotchSize {
        didSet { save(notchSize, forKey: Keys.notchSize) }
    }
    public var displayPlacement: NotchDisplayPlacement {
        didSet { save(displayPlacement, forKey: Keys.displayPlacement) }
    }
    public var showsMenuBarIcon: Bool {
        didSet { save(showsMenuBarIcon, forKey: Keys.showsMenuBarIcon) }
    }

    private let defaults: UserDefaults?

    private enum Keys {
        static let animation = "islet.settings.animation"
        static let switchesToDropTargetOnDrag = "islet.settings.switchesToDropTargetOnDrag"
        static let drawsIdleNotchShape = "islet.settings.drawsIdleNotchShape"
        static let notchSize = "islet.settings.notchSize"
        static let displayPlacement = "islet.settings.displayPlacement"
        static let showsMenuBarIcon = "islet.settings.showsMenuBarIcon"
    }

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        animation = Self.load(NotchAnimation.self, forKey: Keys.animation, from: defaults) ?? .default
        switchesToDropTargetOnDrag = Self.load(Bool.self, forKey: Keys.switchesToDropTargetOnDrag, from: defaults) ?? true
        drawsIdleNotchShape = Self.load(Bool.self, forKey: Keys.drawsIdleNotchShape, from: defaults) ?? false
        notchSize = Self.load(NotchSize.self, forKey: Keys.notchSize, from: defaults) ?? .default
        displayPlacement = Self.load(NotchDisplayPlacement.self, forKey: Keys.displayPlacement, from: defaults) ?? .default
        showsMenuBarIcon = Self.load(Bool.self, forKey: Keys.showsMenuBarIcon, from: defaults) ?? true
    }

    public func resetAnimation() {
        animation = .default
    }

    public func resetAll() {
        animation = .default
        switchesToDropTargetOnDrag = true
        drawsIdleNotchShape = false
        notchSize = .default
        displayPlacement = .default
        showsMenuBarIcon = true
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
