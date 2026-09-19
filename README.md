# Islet

A dynamic notch for macOS, designed as a plugin host: every screen in the notch is a plugin built on the `IsletCore` plugin API.

## Development

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
open Islet.xcodeproj
```

Core logic lives in `Packages/IsletCore` and can be tested without Xcode:

```sh
cd Packages/IsletCore && swift test
```
