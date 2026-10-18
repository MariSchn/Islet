import Foundation
import IsletCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public final class StubPlugin: IsletPlugin {
    public static let manifest = PluginManifest(id: "test.stub", displayName: "Stub", systemImage: "circle")

    public let context: PluginContext
    public var activations = 0
    public var deactivations = 0
    public var activationDelay: Duration = .zero
    public var activationError: (any Error)?
    public var pillAfterActivation: PillStatus?

    public init(context: PluginContext) {
        self.context = context
    }

    public func activate() async throws {
        activations += 1
        if activationDelay > .zero {
            try? await Task.sleep(for: activationDelay)
        }
        if let activationError { throw activationError }
        if let pillAfterActivation { context.pillStatus = pillAfterActivation }
    }

    public var deactivationDelay: Duration = .zero

    public func deactivate() async {
        deactivations += 1
        if deactivationDelay > .zero {
            try? await Task.sleep(for: deactivationDelay)
        }
    }
    public var screenBuilds = 0
    public var acceptedDropTypes: [UTType] = []

    public func makeScreen() -> AnyView {
        screenBuilds += 1
        return AnyView(Text("stub"))
    }
}

public struct StubError: Error, Equatable {
    public init() {}
}

public let secondManifest = PluginManifest(id: "test.second", displayName: "Second", systemImage: "square")

@MainActor
public final class Harness {
    public let defaults: UserDefaults
    public let root: URL
    private let defaultsDirectory: URL

    public init() {
        let name = "IsletTests." + UUID().uuidString
        root = FileManager.default.temporaryDirectory.appending(path: name)
        defaultsDirectory = FileManager.default.temporaryDirectory.appending(path: name + ".defaults")
        defaults = UserDefaults(suiteName: defaultsDirectory.appending(path: "defaults").path)!
    }

    public func makeRegistry() -> PluginRegistry {
        PluginRegistry(storageRoot: root, userDefaults: defaults)
    }

    @discardableResult
    public func registerStub(in registry: PluginRegistry, configure: (StubPlugin) -> Void = { _ in }) async throws -> StubPlugin {
        var created: StubPlugin?
        try await registry.register(manifest: StubPlugin.manifest) { context in
            let plugin = StubPlugin(context: context)
            configure(plugin)
            created = plugin
            return plugin
        }
        return created!
    }

    @discardableResult
    public func registerSecond(in registry: PluginRegistry, configure: (StubPlugin) -> Void = { _ in }) async throws -> StubPlugin {
        var created: StubPlugin?
        try await registry.register(manifest: secondManifest) { context in
            let plugin = StubPlugin(context: context)
            configure(plugin)
            created = plugin
            return plugin
        }
        return created!
    }

    isolated deinit {
        try? FileManager.default.removeItem(at: defaultsDirectory)
        try? FileManager.default.removeItem(at: root)
    }
}
