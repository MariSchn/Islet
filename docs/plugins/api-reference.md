# API reference

Everything below is in the `IsletCore` module (`Packages/IsletCore/Sources/IsletCore`). All plugin-facing types that hold state are `@MainActor`. `IsletCore` contains only what plugins build against; the notch windows, views and settings window live in `IsletHost`, which plugins don't import.

## IsletPlugin

```swift
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
```

`manifest`, `init(context:)` and `makeScreen()` are required. The defaults for the rest are: `activate()` and `deactivate()` do nothing, `acceptedDropTypes` is empty, and `makeSettingsView()` returns `nil`.

| Member | Called | Purpose |
| --- | --- | --- |
| `activate()` | When the plugin is registered while enabled, and each time the user enables it again. | Start work: load state, start timers, servers or observers, set `contentSize` and `pillStatus`. Throwing puts the plugin in the failed state (see [Lifecycle](#lifecycle)). |
| `deactivate()` | When the user disables the plugin, and when the app quits. | Stop everything `activate()` started. On quit, the host waits at most 2 seconds for all plugins together. |
| `makeScreen()` | Once, the first time the host needs the screen. The result is cached for the lifetime of the app. | Return the expanded view. Because it is built only once, it has to observe your model rather than capture values. |
| `acceptedDropTypes` | Whenever the user drags content over the notch. | The types you accept make the notch react to matching drags and switch to this plugin during one (see [Drops](resources-and-concurrency.md#file-drops)). |
| `makeSettingsView()` | Once, when the settings window first lists plugin settings. Cached like the screen. | Return a view for the plugin's settings tab, or `nil` for no tab. |

`init(context:)` is called when the host registers the plugin with `PluginRegistry.register(_:)`. It runs even for plugins the user has disabled, so keep it cheap and start work in `activate()`. Setting up `derive` and `observe` in the initializer is fine: they only read your model.

### Lifecycle

The host tracks each plugin in a `PluginEntry` whose `state` is a `PluginState`:

```swift
public enum PluginState: Sendable {
    case inactive
    case activating
    case active
    case deactivating
    case failed(any Error)
}
```

- Registration creates the context, calls your factory, then awaits `activate()` if the plugin is enabled.
- Enabling and disabling in Settings › Plugins calls `activate()` and `deactivate()`. Transitions for one plugin never overlap: a toggle waits for the previous transition to finish, and `activate()` is not called again while already active.
- While the state is not `.active`, the notch shows a spinner instead of your screen. After a failed `activate()` it shows "<displayName> failed to start: <error.localizedDescription>". The next time the plugin is enabled, `activate()` runs again.
- After `deactivate()` the host clears the plugin's `pillStatus` and announcement. `contentSize` is kept.
- The plugin object, its context and its cached views live until the app quits.

## PluginManifest

```swift
public struct PluginManifest: Sendable, Hashable {
    public let id: String
    public let displayName: String
    public let systemImage: String

    public init(id: String, displayName: String, systemImage: String)

    public var hasValidID: Bool { get }
}
```

- `id` identifies the plugin. It names the storage directory and prefixes the settings keys, and it is used to remember whether the plugin is enabled and which plugin was last selected. Don't change it after release. It must be non-empty, contain only letters, digits, `.`, `-` and `_`, not start with `.` and not contain `..`. Built-in plugins use `islet.<name>`; use your own reverse-DNS prefix, such as `com.example.counter`.
- `displayName` is shown in the settings window, as the tooltip of the tab icon, and in the failure message.
- `systemImage` is an SF Symbol name, used for the tab icon in the navigation row and in the settings window.

`register` throws `PluginRegistryError.invalidID(_:)` for an invalid id and `PluginRegistryError.duplicateID(_:)` if the id is already registered.

## PluginContext

The host creates one context per plugin and passes it to your initializer. It is `@MainActor @Observable`, so SwiftUI views that read it update automatically.

```swift
@MainActor
@Observable
public final class PluginContext {
    public let manifest: PluginManifest
    public let storageDirectory: URL
    public let settings: PluginSettings
    public let logger: Logger
    public var pillStatus: PillStatus?
    public var contentSize: CGSize?
    public internal(set) var isScreenVisible: Bool
    public private(set) var announcement: PillAnnouncement?

    public func announce(_ announcement: PillAnnouncement)
    public func derive<Value: Equatable>(_ property: ReferenceWritableKeyPath<PluginContext, Value>, from value: @escaping @MainActor () -> Value)
    public func observe<Value: Equatable>(_ value: @escaping @MainActor () -> Value, initial: Bool = false, onChange: @escaping @MainActor (Value) -> Void)
}
```

| Member | Details |
| --- | --- |
| `manifest` | The manifest the plugin was registered with. |
| `storageDirectory` | A directory the host created for this plugin: `~/Library/Application Support/Islet/Plugins/<id>/`. See [Settings and storage](settings-and-storage.md#storage-directory). |
| `settings` | Key-value preferences, stored in `UserDefaults` under this plugin's prefix. See [Settings and storage](settings-and-storage.md). |
| `logger` | An `os.Logger` with the app's subsystem and the plugin id as its category, so the plugin's messages can be filtered in Console. |
| `pillStatus` | What the closed notch shows for this plugin, or `nil` for nothing. See [Collapsed pill](collapsed-pill.md). |
| `contentSize` | The size the expanded notch should give your screen, or `nil` for the default. See [Sizing](sizing.md). |
| `isScreenVisible` | `true` while the notch is open on this plugin. Use it to do expensive work, such as frequent polling, only while the screen is seen. |
| `announcement`, `announce(_:)` | A short line shown once below the closed notch. See [Announcements](collapsed-pill.md#announcements). |
| `derive(_:from:)` | Keeps `pillStatus` or `contentSize` equal to a value computed from observable state. See [Deriving state](#deriving-state). |
| `observe(_:initial:onChange:)` | Calls `onChange` whenever the observed value changes, and once with the current value when `initial` is `true`. See [Deriving state](#deriving-state). |

There is no public initializer. To get a context in tests, register the plugin with a `PluginRegistry` (see [Testing](testing.md)).

### Deriving state

Instead of assigning `pillStatus` and `contentSize` whenever your model changes, derive them from it:

```swift
public init(context: PluginContext) {
    self.context = context
    context.derive(\.pillStatus) { [model] in model.pillStatus }
    context.derive(\.contentSize) { [model] in CGSize(width: 360, height: model.isExpanded ? 240 : 120) }
    context.observe({ [model] in model.step }) { context.settings.set($0, forKey: "step") }
}
```

The value is applied while the plugin is active: right after `activate()` returns, and again whenever an `@Observable` property the closure read changes. Updates land on the next turn of the main actor and only when the value differs from the current one. A derived property is also restored if something else overwrites it while the plugin is active; after `deactivate()` nothing is applied, so the host's clearing of the pill sticks until the plugin is enabled again. Values that don't come from observable state, such as the current time, are not tracked: read an observable property that you change when they should be recomputed, as `AgentSessionStore` does for finished sessions that expire.

`observe(_:initial:onChange:)` is for side effects, such as saving a setting or announcing a status change. Like SwiftUI's `onChange(of:initial:)`, `onChange` only runs when the value changes unless `initial` is `true`. Saving settings without `initial` means defaults are never written, so a changed default still reaches users who never touched the setting. Several changes within one turn of the main actor are reported once, with the latest value.

## PluginSettings

```swift
@MainActor
@Observable
public final class PluginSettings {
    public func value<T>(forKey key: String) -> T?
    public func set(_ value: (some Any)?, forKey key: String)
}
```

See [Settings and storage](settings-and-storage.md).

## PillStatus

```swift
public struct PillStatus: Sendable, Equatable {
    public enum Priority: Int, Sendable, Comparable {
        case ambient
        case info
        case attention
        case urgent
    }

    public struct Ring: Sendable, Equatable {
        public struct Segment: Sendable, Equatable {
            public var value: Double
            public var tint: Color.Resolved
            public init(value: Double, tint: Color.Resolved)
        }
        public var segments: [Segment]
        public init(segments: [Segment])
    }

    public var text: String
    public var systemImage: String?
    public var priority: Priority
    public var artwork: CGImage?
    public var ring: Ring?
    public var tint: Color.Resolved?

    public init(text: String, systemImage: String? = nil, priority: Priority = .info, artwork: CGImage? = nil, ring: Ring? = nil, tint: Color.Resolved? = nil)
}
```

See [Collapsed pill](collapsed-pill.md) for how each field is rendered and how `priority` is used.

## PillAnnouncement

```swift
public struct PillAnnouncement: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var text: String
    public var systemImage: String?
    public var tint: Color.Resolved?
    public var priority: PillStatus.Priority

    public init(id: UUID = UUID(), text: String, systemImage: String? = nil, tint: Color.Resolved? = nil, priority: PillStatus.Priority = .info)
}
```

See [Announcements](collapsed-pill.md#announcements).

## Environment: notchAnimation

```swift
extension EnvironmentValues {
    public var notchAnimation: Animation { get set }
}
```

The host sets this on every plugin screen to the animation it uses for expanding the notch, resizing it and switching between plugins, based on the user's animation settings. Use it for changes inside your screen that go together with a `contentSize` change, so both move in step:

```swift
private struct AnimatedList: View {
    @Environment(\.notchAnimation) private var animation
    @State private var expanded = false

    var body: some View {
        VStack { Text("a"); if expanded { Text("b") } }
            .animation(animation, value: expanded)
    }
}
```

## Utilities

- `Duration.milliseconds: Double`: a `Duration` as fractional milliseconds.

## Host-side types

Plugins don't need these at runtime, but they are public and useful in tests:

- `PluginRegistry(storageRoot: URL, userDefaults: UserDefaults = .standard)` owns all plugins. `register(_:) async throws -> PluginEntry` (discardable result) registers and activates a plugin type; `register(manifest:make:)` does the same with a factory closure. `setEnabled(_:for:) async`, `isEnabled(_:)`, `entry(for:)`, `entries` (registration order), `orderedEntries` (the user's order from Settings › Plugins, stored under `islet.pluginOrder`, then any remaining entries in registration order), `enabledEntries` (`orderedEntries` without disabled plugins) and `selectedID` expose the rest of its state. `move(_:by:)` moves an entry within `orderedEntries`, clamped to the ends, and stores the order. `deactivateAll()` deactivates every plugin, and `setNotchExpanded(_:by:)` is how the host reports an open notch.
- `PluginEntry` exposes `manifest`, `context`, `plugin`, `state`, and the cached `screen` and `settingsView`.
- `PluginState.isActive` is `true` only for `.active`.
- `PillSelection` is the user's choice of how the collapsed pill is picked (see [Collapsed pill](collapsed-pill.md#which-plugins-pill-is-shown)).
- `NotchGeometry`, in `IsletHost`, holds the sizing rules (see [Sizing](sizing.md)).
