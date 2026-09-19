import SwiftUI

@MainActor
public protocol IsletPlugin: AnyObject {
    func activate() async throws
    func deactivate() async

    func makeScreen() -> AnyView

    var acceptsFileDrops: Bool { get }
}

public extension IsletPlugin {
    func activate() async throws {}
    func deactivate() async {}
    var acceptsFileDrops: Bool { false }
}
