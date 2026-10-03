---
name: new-plugin
description: Scaffold a new Islet plugin package (Package.swift, plugin class, screen, test target), wire it into project.yml and AppDelegate.builtInPlugins, and build and test it. Use when the user asks to create, add or start a new plugin for the notch.
---

# New Islet plugin

Creates `Plugins/<Name>Plugin/` as a Swift package that builds against `IsletCore` only, registers it with the app and verifies it builds and its tests pass. The plugin guide in `docs/plugins/` explains every API used here; read the relevant page before going beyond the scaffold.

## 1. Settle the basics

Ask the user for anything that isn't clear from the request:

- **Name**: UpperCamelCase without the `Plugin` suffix, e.g. `Timer`. The package, module and class are `<Name>Plugin`.
- **Manifest id**: `islet.<name>` for plugins that ship with Islet, otherwise reverse DNS such as `com.example.timer`. Letters, digits, `.`, `-` and `_` only. Never change it after release: it names the storage directory and prefixes the settings keys.
- **Display name** and **SF Symbol** for the tab icon.
- Whether it needs a **pill**, a **settings pane**, **file drops** or **background work**.

Check that `Plugins/<Name>Plugin` doesn't exist yet and that no manifest in `Plugins/*/Sources` uses the same id.

## 2. Create the package

`Plugins/<Name>Plugin/Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "<Name>Plugin",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "<Name>Plugin", targets: ["<Name>Plugin"])
    ],
    dependencies: [
        .package(path: "../../Packages/IsletCore")
    ],
    targets: [
        .target(name: "<Name>Plugin", dependencies: ["IsletCore"]),
        .testTarget(name: "<Name>PluginTests", dependencies: ["<Name>Plugin"])
    ]
)
```

Add `resources: [.process("Resources")]` to the target only when the plugin bundles files.

`Plugins/<Name>Plugin/Sources/<Name>Plugin/<Name>Plugin.swift`. Keep state in an `@Observable` model, derive the pill and size from it, and keep everything except the plugin class and its protocol members internal:

```swift
import IsletCore
import SwiftUI

@MainActor
public final class <Name>Plugin: IsletPlugin {
    public static let manifest = PluginManifest(id: "<id>", displayName: "<Display Name>", systemImage: "<symbol>")
    static let contentSize = CGSize(width: 360, height: 120)

    let model = <Name>Model()

    public init(context: PluginContext) {
        context.derive(\.contentSize) { Self.contentSize }
        context.derive(\.pillStatus) { [model] in model.pillStatus }
    }

    public func makeScreen() -> AnyView {
        AnyView(<Name>Screen(model: model))
    }
}

@MainActor
@Observable
final class <Name>Model {
    var count = 0

    var pillStatus: PillStatus? {
        count > 0 ? PillStatus(text: "\(count)", systemImage: "<symbol>", priority: .ambient) : nil
    }
}
```

`Plugins/<Name>Plugin/Sources/<Name>Plugin/<Name>Screen.swift`:

```swift
import SwiftUI

struct <Name>Screen: View {
    let model: <Name>Model

    var body: some View {
        HStack {
            Text("\(model.count)")
                .font(.largeTitle.monospacedDigit())
            Spacer()
            Button("Add") { model.count += 1 }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

Replace the counter with the real feature, keeping these rules:

- Start timers, servers and observers in `activate()` and stop them in `deactivate()`; the initializer also runs for disabled plugins.
- Use `context.observe({ [unowned context] in context.isScreenVisible }) { ... }` to slow down work while the screen is hidden.
- Persist preferences with `context.settings` and save them with `context.observe`; put data files in `context.storageDirectory`.
- Log through `context.logger`, never `print` or `NSLog`.
- If the height depends on content, compute it in a static function from the same constants the views use and derive `contentSize` from it.
- Return `makeSettingsView()` only when there is something to configure, and set `acceptedDropTypes` only for plugins that handle dropped content.

## 3. Add tests

`Plugins/<Name>Plugin/Tests/<Name>PluginTests/<Name>PluginTests.swift`:

```swift
import Foundation
import IsletCore
import Testing
@testable import <Name>Plugin

@MainActor
struct <Name>PluginTests {
    @Test func registersAndDerivesItsSizeAndPill() async throws {
        let suite = "<Name>PluginTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        defer { try? FileManager.default.removeItem(at: root) }

        let registry = PluginRegistry(storageRoot: root, userDefaults: defaults)
        let entry = try await registry.register(<Name>Plugin.self)
        let plugin = try #require(entry.plugin as? <Name>Plugin)
        #expect(entry.state.isActive)

        let deadline = ContinuousClock.now + .seconds(2)
        while entry.context.contentSize != <Name>Plugin.contentSize {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
        #expect(entry.context.pillStatus == nil)

        plugin.model.count = 2
        while entry.context.pillStatus?.text != "2" {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
    }
}
```

Derived values arrive on the next turn of the main actor, so wait for them as above instead of checking right away. Test models and size functions directly where possible.

## 4. Register it with the app

In `project.yml`:

- under `packages`: `<Name>Plugin:` with `path: Plugins/<Name>Plugin`
- under `targets.Islet.dependencies`: `- package: <Name>Plugin`
- under `schemes.Islet.test.targets`: `- package: <Name>Plugin/<Name>PluginTests`

In `App/AppDelegate.swift`, add `import <Name>Plugin` in alphabetical order and append `<Name>Plugin.self` to `builtInPlugins`. The list order is the default tab order in the notch; users can reorder the tabs in Settings › Plugins.

If the plugin controls other apps through Apple events, check that `NSAppleEventsUsageDescription` in `project.yml` still describes why.

## 5. Build and test

```sh
swift test --package-path Plugins/<Name>Plugin
xcodegen generate
xcodebuild -project Islet.xcodeproj -scheme Islet -configuration Debug -derivedDataPath DerivedData build
```

Fix every error and warning. Then relaunch with `pkill -x Islet; sleep 1; open DerivedData/Build/Products/Debug/Islet.app` and tell the user what to check in the notch: the tab icon, the expanded screen at the intended size, the pill, and the settings tab if there is one.

## 6. Document it

Add the plugin to the list of example plugins in `docs/plugins/README.md` when it demonstrates something the others don't.
