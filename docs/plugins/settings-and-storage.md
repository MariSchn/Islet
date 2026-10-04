# Settings and storage

## PluginSettings

`context.settings` is a small key-value store for preferences:

```swift
public func value<T>(forKey key: String) -> T?
public func set(_ value: (some PluginSettingsValue)?, forKey key: String)
```

- Values are stored in `UserDefaults.standard` under `plugin.<id>.<key>`, so keys only need to be unique within your plugin.
- Values are property-list types: `Bool`, `Int`, `Double`, `String`, `Data`, `Date`, and arrays or `[String: …]` dictionaries of these, which is what `PluginSettingsValue` covers. Store an enum through its `rawValue`. `value(forKey:)` returns `nil` when the key is missing or the stored value is not of type `T`, so the type has to be known from context: `let step: Int? = context.settings.value(forKey: "step")`, or `?? default` in a typed position.
- Setting `nil` removes the key. Because the parameter is generic, a bare `nil` literal doesn't compile; spell out the type, as in `context.settings.set(String?.none, forKey: "greeting")`.
- `PluginSettings` is `@Observable`. A SwiftUI view that reads a value in its `body` updates when any value of the plugin changes.
- Settings are not affected by resetting all settings in the General tab, and they survive disabling the plugin.

For anything more than a few flags, or for state that isn't a preference, write a file to the [storage directory](#storage-directory) instead.

## Settings pane

Return a view from `makeSettingsView()` to get a tab under "Plugin Settings" in the settings window's sidebar. The tab shows your `displayName` and `systemImage`, and it is only listed while the plugin is enabled.

The host places your view below a header with the plugin's icon, name and a one-line description, and applies `.formStyle(.grouped)`, so a `Form` with `Section`s matches the rest of the window:

```swift
public func makeSettingsView() -> AnyView? {
    AnyView(CounterSettings(settings: context.settings))
}

private struct CounterSettings: View {
    let settings: PluginSettings

    private var step: Binding<Int> {
        Binding(
            get: { settings.value(forKey: "step") ?? 1 },
            set: { settings.set($0, forKey: "step") }
        )
    }

    var body: some View {
        Form {
            Stepper("Step: \(step.wrappedValue)", value: step, in: 1...10)
        }
    }
}
```

Like the screen, the settings view is built once and cached, so it has to read live state rather than capture it.

Two patterns from the built-in plugins:

- Bind directly to `PluginSettings`, as above and as `HelloPlugin` does.
- Keep the setting as a property of your `@Observable` model and persist it with `context.observe`. `MediaPlugin` reads `showsPill` from settings in `init`, passes it to `MediaController`, and saves changes with `context.observe({ controller.showsPill }) { settings.set($0, forKey: Self.showsPillKey) }`. Its settings view binds to the model with `@Bindable`, and the model reacts to changes immediately. `AgentsPlugin` keeps its alert and display settings in structs and lists each field's key once, in key path tables used for both loading and saving.

## Storage directory

`context.storageDirectory` is `~/Library/Application Support/Islet/Plugins/<id>/`. The host creates it before your initializer runs, and nothing else writes to it. Use it for data files, caches and anything that should survive a restart:

```swift
let url = context.storageDirectory.appending(path: "state.json")
```

`ShelfPlugin` is the reference: `ShelfStore` keeps its items in `shelf.json` in this directory, loads it in `activate()`, and saves after every change. If the file can't be decoded, it is renamed to `shelf.json.corrupt` rather than overwritten, so the user's data is not lost. Copies of dropped files live in `Items/<id>/` in the same directory and are deleted when the item or the shelf is removed. The preference for when to keep a copy is a `PluginSettings` value, not part of that file.

Islet does not delete the directory when a plugin is disabled.
