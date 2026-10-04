# Contributing to Islet

Thanks for helping! Bug reports, plugin ideas and pull requests are all welcome.

## Building

You need macOS 15 or later, Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The Xcode project is generated from `project.yml` and not checked in.

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project Islet.xcodeproj -scheme Islet -configuration Debug -derivedDataPath DerivedData build
open DerivedData/Build/Products/Debug/Islet.app
```

Run `xcodegen generate` again after you add files or packages. Quit the release version of Islet first; two copies fight over the notch and the local ports.

## Testing

```sh
xcodebuild -project Islet.xcodeproj -scheme Islet -derivedDataPath DerivedData test
```

Each package can also be tested on its own, which is faster:

```sh
swift test --package-path Packages/IsletCore
swift test --package-path Plugins/AgentsPlugin
```

Tests use [Swift Testing](https://developer.apple.com/documentation/testing). CI runners are slower than your Mac, so wait for conditions with a deadline instead of sleeping for a fixed time.

## Layout

- `Packages/IsletCore`: the plugin API (`IsletPlugin`, `PluginContext`, pills, settings) and the plugin registry. Plugins only import this.
- `Packages/IsletHost`: the notch windows and animations, the settings window and the app settings. It is the only package that uses private macOS API.
- `Plugins/<Name>Plugin`: one Swift package per plugin, with its tests.
- `App`: the app delegate that registers the built-in plugins.

The [plugin developer guide](docs/plugins/README.md) explains the API, and `Plugins/HelloPlugin` is the smallest complete example.

## Pull requests

- Keep a pull request to one change, and describe what it does and how you tested it.
- Match the style of the surrounding code. Plugins are `@MainActor final class`es; only the plugin class and its protocol members are `public`.
- Add or update tests for behaviour you change. Size functions such as `contentSize(for:)` have tests that keep them in sync with the views.
- Don't log personal data. Use the plugin's `context.logger` and mark private values `privacy: .private`.

## New plugins

New built-in plugins should be useful to many people and cheap when idle. Open an issue first to discuss the idea. For something personal, build the plugin in your fork: add its package to `project.yml` (packages, app dependencies and the scheme's test targets) and its type to `builtInPlugins` in `App/AppDelegate.swift`. The `/new-plugin` skill in Claude Code does all of that for you.
