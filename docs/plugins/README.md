# Building Islet plugins

Everything Islet shows in the notch comes from a plugin. A plugin is a Swift package that depends on `IsletCore` and provides one class conforming to `IsletPlugin`. The host app links the package, registers the plugin at launch and takes care of the notch window, hover and expansion, navigation between plugins, the settings window and per-plugin storage.

A plugin contributes up to four things:

| What | How |
| --- | --- |
| The expanded screen | `makeScreen()` returns the SwiftUI view shown below the navigation row when the notch is open. |
| Its size | `context.contentSize` tells the host how big the expanded area should be. `context.derive(\.contentSize) { ... }` keeps it in sync with your model. |
| The collapsed pill | `context.pillStatus` shows a short status next to the closed notch, and can be derived the same way; `context.announce(_:)` briefly shows a line below it. |
| A settings pane | `makeSettingsView()` adds a tab to the Islet settings window. |

## Pages

1. [Getting started](getting-started.md): create a plugin package, register it with the app, build and run.
2. [API reference](api-reference.md): `IsletPlugin`, `PluginManifest`, `PluginContext` and the other `IsletCore` types a plugin uses, plus the lifecycle.
3. [Sizing and the notch](sizing.md): how `contentSize` becomes the expanded notch, clamping and the notch size setting.
4. [Collapsed pill and announcements](collapsed-pill.md): `PillStatus`, priorities, how the host picks which plugin's pill to show, and `PillAnnouncement`.
5. [Settings and storage](settings-and-storage.md): `PluginSettings`, the settings pane and the storage directory.
6. [Resources and concurrency](resources-and-concurrency.md): bundled resources, file drops, Swift 6 and main-actor rules.
7. [Testing](testing.md): test targets, running tests and getting a real `PluginContext` in a test.

## Example plugins

All built-in plugins live in `Plugins/` and use only the public `IsletCore` API, so they double as examples:

- `HelloPlugin`: the minimal example, registered in Debug builds only. It covers a screen, a settings view, pill priorities and resizing at runtime.
- `ShelfPlugin`: file drops (`acceptsFileDrops`), state that persists as JSON in `context.storageDirectory`, a width derived from the number of items, and logging through `context.logger`.
- `MediaPlugin`: polling in `activate()`/`deactivate()` that slows down while its screen is hidden (`context.isScreenVisible`), a derived pill with artwork and tint, interchangeable data sources with per-source capabilities, a height that grows while a list is open, and stubbed sources in tests.
- `AgentsPlugin`: a local server started in `activate()`, a pill and content size derived from its session store, a ring pill, announcements driven by `context.observe`, bundled resources (`Bundle.module`) and a large settings pane.
- `GitHubPlugin`: running a command-line tool (`gh`) with `Process` off the main actor with a timeout, polling that speeds up while the screen is visible and backs off after failures, pausing while `NWPathMonitor` reports no network, a ring pill derived from the fetched data with a setting to hide it, and a stubbed client in tests registered through `register(manifest:make:)`.

## Checklist for a new plugin

With Claude Code, the `new-plugin` skill (`.claude/skills/new-plugin`) scaffolds the package, the plugin class, a test and the app wiring below, then builds and tests the result.

- [ ] `Plugins/<Name>Plugin/Package.swift` with a library product and a dependency on `../../Packages/IsletCore`.
- [ ] A `@MainActor public final class` conforming to `IsletPlugin`, with a `public static let manifest` and `public init(context: PluginContext)`.
- [ ] A unique, valid manifest `id` (see [PluginManifest](api-reference.md#pluginmanifest)).
- [ ] Package listed in `project.yml` under `packages` and as a dependency of the `Islet` target.
- [ ] `import` in `App/AppDelegate.swift` and the type added to `builtInPlugins`.
- [ ] `context.contentSize` set or derived before the notch first opens.
- [ ] `context.pillStatus` cleared (`nil`) when there is nothing to show.
- [ ] Background work started in `activate()` and stopped in `deactivate()`.
