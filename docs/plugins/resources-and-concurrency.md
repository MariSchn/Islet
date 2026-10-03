# Resources and concurrency

## Bundled resources

Put images, sounds, JSON and other files in a `Resources` folder inside the target and declare it in `Package.swift`:

```
Plugins/CounterPlugin/Sources/CounterPlugin/Resources/defaults.json
```

```swift
.target(name: "CounterPlugin", dependencies: ["IsletCore"], resources: [.process("Resources")])
```

Load them through `Bundle.module`, which SwiftPM generates for targets with resources:

```swift
let url = Bundle.module.url(forResource: "defaults", withExtension: "json")
```

`.process` places the files at the top level of the bundle, so look them up by name only (use `.copy` to keep a folder structure). `AgentsPlugin` bundles `Resources/claude.svg` this way and loads it in `ClaudeLogo` with `Bundle.module.url(forResource: "claude", withExtension: "svg")`. `Bundle.module` also works when running tests.

SF Symbols need no bundling. Use them by name in `PluginManifest.systemImage`, `PillStatus.systemImage` and your views.

## Localization

User-visible strings are localized through a string catalog per package. Declare the default language, add `Resources/Localizable.xcstrings` to the target and process the folder:

```swift
let package = Package(
    name: "CounterPlugin",
    defaultLocalization: "en",
    ...
    targets: [
        .target(name: "CounterPlugin", dependencies: ["IsletCore"], resources: [.process("Resources")])
    ]
)
```

Strings in a package are looked up in the main bundle unless you pass the package's bundle, so always use `bundle: .module`:

```swift
Text("Nothing here yet", bundle: .module)
Toggle(String(localized: "Show seconds", bundle: .module), isOn: $showsSeconds)
let title = String(localized: "Read \(fileName)", bundle: .module)
```

`Text` takes `bundle:` directly. Controls such as `Toggle`, `Button`, `Picker` and `Label`, and modifiers such as `.help` and `.accessibilityLabel`, take a plain `String`, so pass them `String(localized:bundle:)`. Without `bundle: .module` the lookup falls back to the app's catalog and shows the English text.

Catalog keys are the English strings; interpolations become `%@` (strings) and `%lld` (integers). Give every key a German entry with state `translated`. Keep file names, commands and other data out of the translated text by interpolating them. The built-in plugins have a completeness test that fails when a key has no translated German entry; copy it from any built-in plugin's `LocalizationTests.swift`.

## File drops

Plugins list the content types they accept in `acceptedDropTypes` (`[UTType]`, empty by default). A drag expands the notch while at least one enabled plugin accepts it: a plugin matches when some dragged type conforms to one of its accepted types, so `.image` matches a dragged `.png` and `.fileURL` matches a dragged file. If the user has "Switch to a plugin that accepts files" turned on (Settings › General, on by default), the notch also switches to the first enabled plugin, in tab order, that matches.

The notch window registers only for the pasteboard types `.fileURL`, `.URL`, `.string`, `.tiff` and `.png`. Drags that carry none of these never reach plugins.

`acceptedDropTypes` only decides whether the notch reacts to a drag and which plugin it switches to. To receive the files, your screen handles the drop itself, as `ShelfScreen` does:

```swift
.onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
    Task { @MainActor in
        let urls = await loadFileURLs(from: providers)
        await store.add(urls)
    }
    return true
}
```

## Working only while visible

`context.isScreenVisible` is `true` while the notch is open on your plugin. Observe it to slow down or pause work nobody can see. `MediaPlugin` polls the player every second while its screen is visible and every 15 seconds otherwise, relying on the player's change notifications in between:

```swift
context.observe({ [unowned context] in context.isScreenVisible }) { controller.isScreenVisible = $0 }
```

## Local servers

Plugins that accept requests from scripts or tools on the same machine use `LocalHTTPServer` (see the [API reference](api-reference.md#localhttpserver)). Start it in `activate()` and stop it in `deactivate()`, since the port stays bound otherwise. Handlers run off the main actor: hop to the main actor to touch plugin state, and check `Task.isCancelled` after long awaits, because the task is cancelled when the client disconnects. Show a failed `start` (port in use) to the user instead of swallowing it.

## Logging

Log through `context.logger`, an `os.Logger` whose category is your plugin id. Mark values that are safe to show in Console with `privacy: .public`; everything else is redacted outside of debugging:

```swift
context.logger.error("Could not load \(url.path, privacy: .public): \(error, privacy: .public)")
```

## Swift 6 concurrency

The app and all packages build in the Swift 6 language mode with strict concurrency checking.

- `IsletPlugin`, `PluginContext` and `PluginSettings` are `@MainActor`. Mark your plugin class and the models your views observe `@MainActor` too, and only touch the context on the main actor.
- `activate()` and `deactivate()` are `async` and run on the main actor. Awaiting inside them is fine, but they block the plugin's state transition, and the host shows a spinner until `activate()` returns. Start long-running work in a `Task` and return:

  ```swift
  func activate() async throws {
      refreshTask = Task { [weak self] in
          while !Task.isCancelled {
              self?.refresh()
              try? await Task.sleep(for: .seconds(5))
          }
      }
  }

  func deactivate() async {
      refreshTask?.cancel()
      refreshTask = nil
  }
  ```

- Move blocking work (file IO, parsing, image decoding) off the main actor with `Task.detached` or an `actor`, and hop back to the main actor to update state. `MediaController` decodes artwork with `await Task.detached { ... }.value`. `ShelfStore` checks file reachability in a detached task, and copies a dropped file there before inserting the item.
- Values that cross actors must be `Sendable`. `PillStatus` and `PillAnnouncement` are, which is why their colors are `Color.Resolved` instead of `Color`.
- For dependencies you want to replace in tests, use a `Sendable` protocol, as `MediaSource` does in `MediaPlugin`.

### Known pitfalls

- **`NSAppleScript` must run on the main actor.** Create and execute scripts from `@MainActor` code, as `InstalledTerminal` in `AgentsPlugin` does:

  ```swift
  @MainActor
  func openTerminal() {
      var error: NSDictionary?
      NSAppleScript(source: "tell application \"Terminal\" to activate")?.executeAndReturnError(&error)
  }
  ```

  Controlling another app needs the user's permission under Privacy & Security › Automation. macOS asks the first time. The app's `NSAppleEventsUsageDescription` is set in `project.yml`; update its text if your plugin controls apps for a new reason.
- **Dates:** static `ISO8601DateFormatter` instances are not `Sendable`. Parse with `try Date(string, strategy: .iso8601)` instead.
- **Observation callbacks:** prefer `context.derive` and `context.observe` over change callbacks. If a model does need a plain closure property, mark it `@ObservationIgnored` so that setting it doesn't trigger view updates.
