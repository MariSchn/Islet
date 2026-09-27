# Islet

A dynamic notch for macOS, designed as a plugin host: every screen in the notch is a plugin built on the `IsletCore` plugin API.

## Development

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
open Islet.xcodeproj
```

Core logic lives in `Packages/IsletCore`. Built-in plugins live in `Plugins/`, each as its own Swift package depending only on `IsletCore`; they are linked into the app and registered in `App/AppDelegate.swift`. The core can be tested without Xcode:

```sh
cd Packages/IsletCore && swift test
```

## Building a plugin

See the [plugin developer guide](docs/plugins/README.md) for a step-by-step walkthrough, the API reference and notes on sizing, the collapsed pill, settings, resources, concurrency and testing.
