import SwiftUI

private struct NotchAnimationKey: EnvironmentKey {
    static let defaultValue = NotchAnimation.default.animation(expanding: true)
}

extension EnvironmentValues {
    public var notchAnimation: Animation {
        get { self[NotchAnimationKey.self] }
        set { self[NotchAnimationKey.self] = newValue }
    }
}
