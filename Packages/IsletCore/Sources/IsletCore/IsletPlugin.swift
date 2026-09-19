import SwiftUI

@MainActor
public protocol IsletPlugin: AnyObject {
    func activate() async throws
    func deactivate() async

    func makeScreen() -> AnyView

    var acceptsFileDrops: Bool { get }

    func makeSettingsView() -> AnyView?
}

public extension IsletPlugin {
    func activate() async throws {}
    func deactivate() async {}
    var acceptsFileDrops: Bool { false }
    func makeSettingsView() -> AnyView? { nil }
}
