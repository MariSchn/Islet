import SwiftUI

@MainActor
public protocol IsletPlugin: AnyObject {
    func activate() async throws
    func deactivate() async

    func makeScreen() -> AnyView
}

public extension IsletPlugin {
    func activate() async throws {}
    func deactivate() async {}
}
