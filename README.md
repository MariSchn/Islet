# Islet

A dynamic notch for macOS, designed as a plugin host: every screen in the notch is a plugin built on the `IsletCore` plugin API.

## Development

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
open Islet.xcodeproj
```

The plugin API lives in `Packages/IsletCore`. The notch windows, the settings window and the rest of the host live in `Packages/IsletHost`, which is the only package that uses private macOS frameworks. Built-in plugins live in `Plugins/`, each as its own Swift package depending only on `IsletCore`; they are linked into the app and listed in `AppDelegate.builtInPlugins` (`App/AppDelegate.swift`). Each package can be tested without Xcode:

```sh
swift test --package-path Packages/IsletCore
swift test --package-path Packages/IsletHost
swift test --package-path Plugins/AgentsPlugin
```

GitHub Actions runs the tests of the whole `Islet` scheme on every pull request (`.github/workflows/ci.yml`).

## Building a plugin

See the [plugin developer guide](docs/plugins/README.md) for a step-by-step walkthrough, the API reference and notes on sizing, the collapsed pill, settings, resources, concurrency and testing.
