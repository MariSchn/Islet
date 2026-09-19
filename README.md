# Islet

A dynamic notch for macOS, built as a plugin host. Shelf, media controls and coding-agent control ship as built-in plugins; external plugins are written in JS/TS.

## Development

Requires Xcode 27+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
open Islet.xcodeproj
```

Core logic lives in `Packages/IsletCore` and can be tested without Xcode:

```sh
cd Packages/IsletCore && swift test
```
