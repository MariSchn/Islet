import SwiftUI

@MainActor
public protocol IsletPlugin: AnyObject {
    static var manifest: PluginManifest { get }

    init(context: PluginContext)

    func activate() async
    func deactivate() async

    func makeScreen() -> AnyView
}

public extension IsletPlugin {
    func activate() async {}
    func deactivate() async {}
}
