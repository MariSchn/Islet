import Foundation
import Observation
import SwiftUI

public enum PluginState: Sendable {
    case inactive
    case activating
    case active
    case deactivating
    case failed(any Error)

    public var isActive: Bool {
        if case .active = self { return true }
        return false
    }
}

public enum NavigationDirection: Sendable, Equatable {
    case forward
    case backward
}

public enum PluginRegistryError: Error, Equatable {
    case duplicateID(String)
    case invalidID(String)
}

@MainActor
@Observable
public final class PluginEntry: @MainActor Identifiable {
    public let manifest: PluginManifest
    public let context: PluginContext
    public let plugin: any IsletPlugin
    public internal(set) var state: PluginState = .inactive

    @ObservationIgnored var pendingTransition: Task<Void, Never>?
    @ObservationIgnored private var cachedScreen: AnyView?
    @ObservationIgnored private var cachedSettingsView: AnyView??

    public var id: String { manifest.id }

    public var screen: AnyView {
        if let cachedScreen { return cachedScreen }
        let screen = plugin.makeScreen()
        cachedScreen = screen
        return screen
    }

    public var settingsView: AnyView? {
        if let cachedSettingsView { return cachedSettingsView }
        let view = plugin.makeSettingsView()
        cachedSettingsView = .some(view)
        return view
    }

    init(manifest: PluginManifest, context: PluginContext, plugin: any IsletPlugin) {
        self.manifest = manifest
        self.context = context
        self.plugin = plugin
    }
}

@MainActor
@Observable
public final class PluginRegistry {
    public private(set) var entries: [PluginEntry] = []
    public private(set) var disabledIDs: Set<String>
    public private(set) var selectedID: String?

    private let storageRoot: URL
    private let userDefaults: UserDefaults
    private let disabledKey = "islet.disabledPlugins"
    private let selectedKey = "islet.selectedPlugin"

    public init(storageRoot: URL, userDefaults: UserDefaults = .standard) {
        self.storageRoot = storageRoot
        self.userDefaults = userDefaults
        self.disabledIDs = Set(userDefaults.stringArray(forKey: disabledKey) ?? [])
        self.selectedID = userDefaults.string(forKey: selectedKey)
    }

    public var enabledEntries: [PluginEntry] {
        entries.filter { !disabledIDs.contains($0.id) }
    }

    public var activePill: PillStatus? {
        enabledEntries
            .compactMap(\.context.pillStatus)
            .max { $0.priority < $1.priority }
    }

    public var selectedContentSize: CGSize? {
        enabledEntries.first { $0.id == selectedID }?.context.contentSize
    }

    public var preferredDropTarget: PluginEntry? {
        enabledEntries.first { $0.plugin.acceptsFileDrops }
    }

    public func entry(for id: String) -> PluginEntry? {
        entries.first { $0.id == id }
    }

    public func isEnabled(_ id: String) -> Bool {
        !disabledIDs.contains(id)
    }

    @discardableResult
    public func register(
        manifest: PluginManifest,
        make: (PluginContext) -> any IsletPlugin
    ) async throws -> PluginEntry {
        guard manifest.hasValidID else { throw PluginRegistryError.invalidID(manifest.id) }
        guard entry(for: manifest.id) == nil else { throw PluginRegistryError.duplicateID(manifest.id) }

        let storageDirectory = storageRoot.appending(path: manifest.id, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)

        let context = PluginContext(
            manifest: manifest,
            storageDirectory: storageDirectory,
            settings: PluginSettings(pluginID: manifest.id, defaults: userDefaults)
        )
        let entry = PluginEntry(manifest: manifest, context: context, plugin: make(context))
        entries.append(entry)

        if isEnabled(manifest.id) {
            await transition(entry, toActive: true)
            ensureSelection()
        }
        return entry
    }

    public func setEnabled(_ enabled: Bool, for id: String) async {
        guard let entry = entry(for: id), isEnabled(id) != enabled else { return }

        if enabled {
            disabledIDs.remove(id)
        } else {
            disabledIDs.insert(id)
        }
        userDefaults.set(Array(disabledIDs).sorted(), forKey: disabledKey)

        await transition(entry, toActive: enabled)
        if !isEnabled(id) {
            entry.context.pillStatus = nil
        }
        ensureSelection()
    }

    public func select(_ id: String?) {
        guard id == nil || (entry(for: id!) != nil && isEnabled(id!)) else { return }
        selectedID = id
        userDefaults.set(id, forKey: selectedKey)
    }

    @discardableResult
    public func selectNeighbor(_ direction: NavigationDirection) -> Bool {
        let enabled = enabledEntries
        guard let selectedID, let index = enabled.firstIndex(where: { $0.id == selectedID }) else { return false }
        let target = direction == .forward ? index + 1 : index - 1
        guard enabled.indices.contains(target) else { return false }
        select(enabled[target].id)
        return true
    }

    private func ensureSelection() {
        let enabled = enabledEntries
        if let selectedID, enabled.contains(where: { $0.id == selectedID }) { return }
        select(enabled.first?.id)
    }

    private func transition(_ entry: PluginEntry, toActive: Bool) async {
        await entry.pendingTransition?.value

        let task = Task { @MainActor in
            if toActive {
                guard !entry.state.isActive else { return }
                entry.state = .activating
                do {
                    try await entry.plugin.activate()
                    entry.state = .active
                } catch {
                    entry.state = .failed(error)
                }
            } else {
                guard entry.state.isActive else { return }
                entry.state = .deactivating
                await entry.plugin.deactivate()
                entry.state = .inactive
            }
        }
        entry.pendingTransition = task
        await task.value
        if entry.pendingTransition == task {
            entry.pendingTransition = nil
        }
    }
}
