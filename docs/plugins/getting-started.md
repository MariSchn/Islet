# Getting started

This walks through a small "Counter" plugin: a screen with a number and a button. Later pages extend it with a pill and settings.

Requirements: Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). Islet targets macOS 15 and Swift 6 (strict concurrency), and uses Swift 6.2 features such as isolated conformances.

## 1. Create the package

```
Plugins/CounterPlugin/
├── Package.swift
└── Sources/CounterPlugin/
    └── CounterPlugin.swift
```

`Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CounterPlugin",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CounterPlugin", targets: ["CounterPlugin"])
    ],
    dependencies: [
        .package(path: "../../Packages/IsletCore")
    ],
    targets: [
        .target(name: "CounterPlugin", dependencies: ["IsletCore"])
    ]
)
```

A plugin package depends only on `IsletCore`, not on the app or on other plugins.

## 2. Write the plugin

`Sources/CounterPlugin/CounterPlugin.swift`:

```swift
import IsletCore
import SwiftUI

@MainActor
public final class CounterPlugin: IsletPlugin {
    public static let manifest = PluginManifest(id: "com.example.counter", displayName: "Counter", systemImage: "number")

    private let context: PluginContext
    private let model = CounterModel()

    public init(context: PluginContext) {
        self.context = context
    }

    public func activate() async throws {
        context.contentSize = CGSize(width: 360, height: 120)
    }

    public func makeScreen() -> AnyView {
        AnyView(CounterScreen(model: model))
    }
}

@MainActor
@Observable
final class CounterModel {
    var count = 0
}

private struct CounterScreen: View {
    let model: CounterModel

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

The conventions, which all built-in plugins follow:

- The class is `@MainActor public final class`, because `IsletPlugin` is main-actor isolated.
- `public static let manifest` holds the identity the host registers the plugin under. It is required by `IsletPlugin`.
- `public init(context: PluginContext)` keeps the context. It is also required by `IsletPlugin`: the host creates the context and hands it to your initializer.
- State lives in an `@Observable` model owned by the plugin, not in `@State` of the screen. The host calls `makeScreen()` once and reuses the view, and it may show it on several displays at once.
- `activate()` sets `context.contentSize`, so the notch opens at the right size. Without it the notch uses a default of 520 × 220 points (see [Sizing](sizing.md)).

## 3. Add the package to the Xcode project

The Xcode project is generated from `project.yml`. Add the package and make the app target depend on it:

```yaml
packages:
  # ...
  CounterPlugin:
    path: Plugins/CounterPlugin
targets:
  Islet:
    dependencies:
      # ...
      - package: CounterPlugin
```

## 4. Register the plugin

In `App/AppDelegate.swift`, import the module and add the type to `builtInPlugins`:

```swift
import CounterPlugin

static let builtInPlugins: [any IsletPlugin.Type] = [
    // ...
    CounterPlugin.self,
]
```

The order of the list is the order of the tabs in the notch's navigation row. Each plugin is registered on its own, so a plugin that fails to register (for example because of a duplicate or invalid id) is logged and skipped without affecting the others.

New plugins are enabled by default. Users can turn them off under Settings › Plugins.

## 5. Build and run

```sh
xcodegen generate
xcodebuild -project Islet.xcodeproj -scheme Islet -configuration Debug -derivedDataPath DerivedData build
pkill -x Islet; sleep 1; open DerivedData/Build/Products/Debug/Islet.app
```

You can also open `Islet.xcodeproj` and run the `Islet` scheme. Re-run `xcodegen generate` whenever you change `project.yml`. Files inside the package are picked up by SwiftPM without regenerating.

Hover over the notch to expand it (or click it, when Settings › Notch › Open on is set to Click), then click the plugin's icon in the left part of the navigation row, or swipe horizontally with two fingers to switch between plugins. Swipes over a horizontally scrollable `ScrollView` whose content is wider than the view scroll it instead of switching plugins.

## Next steps

- Show something while the notch is closed: [Collapsed pill and announcements](collapsed-pill.md).
- Add user preferences: [Settings and storage](settings-and-storage.md).
- Grow and shrink with your content: [Sizing and the notch](sizing.md).
- Add tests: [Testing](testing.md).
