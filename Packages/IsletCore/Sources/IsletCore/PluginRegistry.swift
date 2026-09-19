import Foundation
import Observation

@MainActor
@Observable
public final class PluginRegistry {
    public struct Entry: Identifiable {
        public let manifest: PluginManifest
        public let context: PluginContext
        public let plugin: any IsletPlugin

        public var id: String { manifest.id }
    }

    public private(set) var entries: [Entry] = []
    public private(set) var disabledIDs: Set<String>
    public var selectedID: String?

    private let storageRoot: URL
    private let userDefaults: UserDefaults
    private let disabledKey = "islet.disabledPlugins"

    public init(storageRoot: URL, userDefaults: UserDefaults = .standard) {
        self.storageRoot = storageRoot
        self.userDefaults = userDefaults
        self.disabledIDs = Set(userDefaults.stringArray(forKey: disabledKey) ?? [])
    }

    public var enabledEntries: [Entry] {
        entries.filter { !disabledIDs.contains($0.id) }
    }

    public var activePill: PillStatus? {
        enabledEntries
            .compactMap(\.context.pillStatus)
            .max { $0.priority < $1.priority }
    }

    public func entry(for id: String) -> Entry? {
        entries.first { $0.id == id }
    }

    public func isEnabled(_ id: String) -> Bool {
        !disabledIDs.contains(id)
    }

    @discardableResult
    public func register<P: IsletPlugin>(_ type: P.Type) async -> Entry {
        let manifest = P.manifest
        precondition(entry(for: manifest.id) == nil, "Plugin \(manifest.id) registered twice")

        let context = PluginContext(
            manifest: manifest,
            storageDirectory: storageRoot.appending(path: manifest.id, directoryHint: .isDirectory),
            settings: userDefaults
        )
        let entry = Entry(manifest: manifest, context: context, plugin: P(context: context))
        entries.append(entry)

        if isEnabled(manifest.id) {
            await entry.plugin.activate()
        }
        if selectedID == nil, isEnabled(manifest.id) {
            selectedID = manifest.id
        }
        return entry
    }

    public func setEnabled(_ enabled: Bool, for id: String) async {
        guard let entry = entry(for: id), isEnabled(id) != enabled else { return }

        if enabled {
            disabledIDs.remove(id)
            await entry.plugin.activate()
        } else {
            disabledIDs.insert(id)
            await entry.plugin.deactivate()
            entry.context.pillStatus = nil
            if selectedID == id {
                selectedID = enabledEntries.first?.id
            }
        }
        userDefaults.set(Array(disabledIDs).sorted(), forKey: disabledKey)
    }
}
