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

## File drops

Files dragged over the notch expand it. If the user has "Switch to a plugin that accepts files" turned on (Settings › General, on by default), the notch also switches to the first enabled plugin whose `acceptsFileDrops` is `true`.

`acceptsFileDrops` only controls that switch. To receive the files, your screen handles the drop itself, as `ShelfScreen` does:

```swift
.onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
    Task { @MainActor in
        let urls = await loadFileURLs(from: providers)
        store.add(urls)
    }
    return true
}
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

- Move blocking work (file IO, parsing, image decoding) off the main actor with `Task.detached` or an `actor`, and hop back to the main actor to update state. `MediaController` decodes artwork with `await Task.detached { ... }.value`. `ShelfStore` checks file reachability in a detached task.
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
- **Observation callbacks:** plain closure properties on an `@Observable` model, such as change callbacks, should be marked `@ObservationIgnored` so that setting them doesn't trigger view updates.
