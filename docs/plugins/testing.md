# Testing

Plugins are tested with Swift Testing (`import Testing`, `@Test`, `#expect`) in a test target of the plugin package.

## Add a test target

```
Plugins/CounterPlugin/Tests/CounterPluginTests/CounterPluginTests.swift
```

```swift
targets: [
    .target(name: "CounterPlugin", dependencies: ["IsletCore"]),
    .testTarget(name: "CounterPluginTests", dependencies: ["CounterPlugin"])
]
```

To run the tests with the rest of the app's tests, add the target to the `Islet` scheme in `project.yml` and run `xcodegen generate`:

```yaml
schemes:
  Islet:
    test:
      targets:
        # ...
        - package: CounterPlugin/CounterPluginTests
```

## Run the tests

From the plugin's directory, without Xcode:

```sh
cd Plugins/CounterPlugin && swift test
```

Through the Xcode scheme, only this plugin's tests:

```sh
xcodebuild -project Islet.xcodeproj -scheme Islet -configuration Debug -derivedDataPath DerivedData test -only-testing:CounterPluginTests
```

## Testing with a real PluginContext

`PluginContext` has no public initializer. To test code that uses it, register the plugin with a `PluginRegistry` backed by a temporary directory and a throwaway `UserDefaults` suite, so tests never touch the user's real settings or files:

```swift
import Foundation
import IsletCore
import Testing
@testable import CounterPlugin

@MainActor
struct CounterPluginTests {
    @Test func setsContentSizeOnActivation() async throws {
        let suite = "CounterPluginTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        defer { try? FileManager.default.removeItem(at: root) }

        let registry = PluginRegistry(storageRoot: root, userDefaults: defaults)
        let entry = try await registry.register(manifest: CounterPlugin.manifest) { CounterPlugin(context: $0) }

        #expect(entry.state.isActive)
        #expect(entry.context.contentSize == CGSize(width: 360, height: 120))
    }
}
```

`register` awaits `activate()`, so the plugin is active when it returns. Use `await registry.setEnabled(false, for: CounterPlugin.manifest.id)` to exercise `deactivate()`. Suites that touch the plugin or the context must be `@MainActor`.

## What to test

The built-in plugins keep most logic out of the plugin class and the views, in models that are easy to test on their own:

- **Models with injected dependencies.** `MediaController` takes a `MediaSource`, and the tests pass a stub source to check the published pill without Spotify. Pass an `onPillChange`-style callback instead of the context to make the model testable without a registry.
- **Storage.** `ShelfStoreTests` creates a `ShelfStore` on a temporary directory and checks saving, loading and handling of a corrupt file.
- **Sizing.** `AgentsPluginTests` calls `AgentsPlugin.contentSize(for:expanded:showsUsage:)` with different states and checks the heights, which keeps the size calculation in sync with the layout constants.

Expanded views, the pill's appearance and the notch animation are not covered by unit tests. Check them by building and running the app.
