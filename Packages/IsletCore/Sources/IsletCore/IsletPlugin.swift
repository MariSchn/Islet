import SwiftUI
import UniformTypeIdentifiers

@MainActor
public protocol IsletPlugin: AnyObject {
    static var manifest: PluginManifest { get }

    init(context: PluginContext)

    func activate() async throws
    func deactivate() async

    func makeScreen() -> AnyView

    var acceptedDropTypes: [UTType] { get }

    func makeSettingsView() -> AnyView?
}

public extension IsletPlugin {
    func activate() async throws {}
    func deactivate() async {}
    var acceptedDropTypes: [UTType] { [] }
    func makeSettingsView() -> AnyView? { nil }
}
