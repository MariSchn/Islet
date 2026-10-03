<div align="center">

<img src="docs/assets/icon.png" width="128" height="128" alt="Islet app icon">

# Islet

**Your MacBook's notch, finally pulling its weight.**

Islet turns the notch into a home for small, glanceable tools. Every screen is a plugin written in a few lines of SwiftUI. It ships with three to get you started, and the next one is yours to build.

<a href="#-getting-started"><img src="https://img.shields.io/badge/macOS_15+-111?style=flat&logo=apple&logoColor=white" width="133" alt="macOS 15+"></a>
<a href="https://www.swift.org"><img src="https://img.shields.io/badge/Swift_6-111?style=flat&logo=swift&logoColor=F05138" width="94" alt="Swift 6"></a>
<a href="#-build-your-own-plugin"><img src="https://img.shields.io/badge/Plugins_in_SwiftUI-111?style=flat&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI%2BPHBhdGggZmlsbD0iI0I5OENGRiIgZD0iTTEwIDMuNWEyIDIgMCAwIDEgNCAwVjVoNGExIDEgMCAwIDEgMSAxdjRoMS41YTIgMiAwIDAgMSAwIDRIMTl2NGExIDEgMCAwIDEtMSAxaC00di0xLjVhMiAyIDAgMCAwLTQgMFYxOUg2YTEgMSAwIDAgMS0xLTF2LTRoMS41YTIgMiAwIDAgMCAwLTRINVY2YTEgMSAwIDAgMSAxLTFoNHoiLz48L3N2Zz4%3D" width="175" alt="Plugins in SwiftUI"></a>
<a href="#-private-by-design"><img src="https://img.shields.io/badge/100%25_local-111?style=flat&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI%2BPHBhdGggZmlsbD0iIzMyRDc0QiIgZD0iTTEyIDEuNWE1LjUgNS41IDAgMCAwLTUuNSA1LjV2M0g1LjhBMS44IDEuOCAwIDAgMCA0IDExLjh2OS40QTEuOCAxLjggMCAwIDAgNS44IDIzaDEyLjRhMS44IDEuOCAwIDAgMCAxLjgtMS44di05LjRhMS44IDEuOCAwIDAgMC0xLjgtMS44aC0uN1Y3QTUuNSA1LjUgMCAwIDAgMTIgMS41Wm0wIDIuNWEzIDMgMCAwIDEgMyAzdjNIOVY3YTMgMyAwIDAgMSAzLTNaIi8%2BPC9zdmc%2B" width="125" alt="100% local"></a>

[Why Islet](#why-islet) · [Build a plugin](#-build-your-own-plugin) · [Built-in plugins](#-built-in-plugins) · [Getting started](#-getting-started) · [Architecture](#-architecture) · [FAQ](#-faq)

<br>

<img src="docs/assets/notch-demo.gif" width="880" alt="Islet in action: the collapsed notch announces that an agent needs you, expands on hover, the permission is approved from the notch, and the notch switches to the music player">

</div>

<br>

## Why Islet?

The notch sits in the most valuable spot on your screen and does nothing. Islet makes it a quiet status bar that grows into a full panel when you hover over it, and lets you decide what lives there.

- 🧩 **Everything is a plugin.** The built-in screens use exactly the same public API as yours. Nothing is special-cased.
- ⚡️ **One class and a SwiftUI view.** No windows, no AppKit, no private APIs. Islet handles the notch shape, hover, animations, displays and settings for you.
- 🎁 **Useful out of the box.** Mission control for coding agents, a music player and a file shelf ship as ready-made plugins, and double as reference implementations.
- 🪄 **Feels like part of macOS.** Spring animations, a collapsed status pill, every display, a settings tab per plugin. Your plugin gets all of it for free.

<br>

## 🧩 Build your own plugin

A plugin is one class plus a SwiftUI view. This is a complete clock for your notch:

```swift
import IsletCore
import SwiftUI

@MainActor
public final class ClockPlugin: IsletPlugin {
    public static let manifest = PluginManifest(
        id: "com.example.clock",
        displayName: "Clock",
        systemImage: "clock"
    )

    private let context: PluginContext

    public init(context: PluginContext) {
        self.context = context
    }

    public func activate() async throws {
        context.contentSize = CGSize(width: 320, height: 120)
    }

    public func makeScreen() -> AnyView {
        AnyView(
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(timeline.date, style: .time)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        )
    }
}
```

### What your plugin gets

Every plugin receives a `PluginContext`. Set a property and the host takes care of the rest:

| | |
|---|---|
| 📐 **`contentSize`** | Grow or shrink the notch to fit your content, animated. |
| 💊 **`pillStatus`** | Show text, an icon, a status ring or artwork in the collapsed notch, with a priority so urgent things always get through. |
| 📣 **`announce(_:)`** | Flash a short message below the collapsed notch. |
| ⚙️ **`settings`** + **`makeSettingsView()`** | Persist preferences and get your own tab in the settings window. |
| 📥 **`acceptsFileDrops`** | Receive files dragged onto the notch. Islet switches to your plugin automatically. |
| 🗂 **`storageDirectory`**, **`logger`** | A private folder for your data and an `os.Logger` scoped to your plugin. |

### From idea to notch in minutes

- **With Claude Code:** the repository ships a `/new-plugin` skill. Describe your idea and it scaffolds the package, the plugin class, the screen and a test target, registers the plugin with the app, then builds and tests it.
- **By hand:** create a Swift package that depends on `IsletCore`, add it to `project.yml` and list your class in `AppDelegate.builtInPlugins`. The [getting started guide](docs/plugins/getting-started.md) walks through every step.

📖 The **[plugin developer guide](docs/plugins/README.md)** covers the full API, sizing, the collapsed pill, settings and storage, resources, concurrency and testing.

### 💡 Ideas for your notch

Pomodoro timer · next meeting from your calendar · CI and pull request status · system stats · clipboard history · smart home toggles · build progress for your dev server · a quick translator · stock or crypto ticker · world clocks for a remote team

<br>

## 🎁 Built-in plugins

Islet comes with three plugins. They are ordinary plugins built on the same API as yours: use them as they are, switch off the ones you don't need, or read their source as examples.

### 🤖 Agents

<img src="docs/assets/agents.png" alt="The Agents screen: Claude usage limits, a session asking to run git push with Allow and Deny buttons, a working session and a finished Codex session on a remote host">

Mission control for your coding agents. Islet installs lightweight hooks for **Claude Code** and **Codex** and shows every session live:

- **Approve without leaving your flow.** Permission requests and agent questions show up in the notch with **Allow** / **Deny** or the answer options.
- **Know what each agent is doing.** Working, needs you, finished or failed, with the current tool call, your last prompt, a turn timer and the recent tool calls when you expand a row.
- **Jump to the session.** One click brings the exact tab to the front in Terminal and iTerm2, the project window in VS Code, Cursor and VSCodium, and Ghostty or WezTerm when that's where the agent runs.
- **Remote machines.** Sessions on servers you reach over SSH show up too, labelled with the host name and flagged when the tunnel goes quiet.
- **Claude usage limits.** Your 5-hour and weekly quota and when each resets, read from Claude Code's own status line. Islet never reads your credentials or calls any API.
- **Alerts your way.** A sound, a macOS notification or a short announcement in the notch when an agent needs you or finishes.

### 🎧 Media

<img src="docs/assets/media.png" alt="The Media screen: album artwork, track title and artist, shuffle, previous, pause, next and repeat buttons and a timeline">

- Controls **Spotify** and **Apple Music**: play/pause, skip, shuffle, repeat and a seekable timeline.
- Browse your playlists and start one right from the notch.
- The controls pick up their tint from the album artwork.
- Optionally shows the current artwork in the collapsed notch.

### 📥 Shelf

<img src="docs/assets/shelf.png" alt="The Shelf screen with a PDF, a Keynote file, an image, a folder and a zip archive">

- Drag files onto the notch and Islet switches to the Shelf automatically.
- Drag them back out into any app, open them or reveal them in Finder.
- The Shelf survives restarts and dims files that were moved or deleted.

<br>

## 🪄 What every plugin gets from the host

### 💊 The pill

<img src="docs/assets/pill.png" alt="The collapsed notch showing a status ring and the announcement 'islet · readme needs you'">

While collapsed, the notch grows a small pill next to the camera housing. Any plugin can put something there: a status ring, album artwork, a short text or an icon. Islet shows the most important one, and anything urgent always gets through.

### 🍎 Feels like part of macOS

- **Hover to open**, move away to close, with an adjustable delay. Swipe with two fingers to switch plugins.
- **Spring animations** with adjustable bounce, or a plain ease-out curve if you prefer calm.
- **Three sizes** for the expanded notch.
- **Every display.** The built-in screen, the primary display, all displays or a specific monitor. Displays without a notch get a virtual one.
- **Menu bar icon** optional, **open at login** optional, and a settings window with a tab for each plugin. Plugins can be switched off one by one.

<br>

## 🔒 Private by design

| | |
|---|---|
| 🏠 **Runs on your Mac** | No accounts, no analytics, no Islet servers. The only outbound request is the album artwork the Media plugin loads from your music service. |
| 🔑 **No credentials** | Islet never touches your Keychain or API keys. Claude usage limits come from the data Claude Code already hands to its status line. |
| 📜 **Readable hooks** | The agent hooks are a short shell script in `~/.claude` / `~/.codex` that talks to Islet over `127.0.0.1`. Read it, and remove it from the settings at any time. |
| 🎛️ **Opt-in** | Music control asks macOS for permission first; the agent hooks, macOS notifications and the status line integration are off until you turn them on. |

<br>

## 🚀 Getting started

**Requirements:** macOS 15 Sequoia or later, Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
git clone https://github.com/MariSchn/Islet.git
cd Islet
xcodegen generate
xcodebuild -project Islet.xcodeproj -scheme Islet -configuration Release -derivedDataPath DerivedData build
open DerivedData/Build/Products/Release/Islet.app
```

Or open `Islet.xcodeproj` in Xcode and press <kbd>⌘</kbd> <kbd>R</kbd>.

**First launch:** hover over the notch, and that's it. Some built-in plugins need a one-time setup:

1. **Agents:** open **Settings › Agents › Install Hooks**, then restart any sessions that were already running. Codex additionally needs its hooks feature enabled in `~/.codex/config.toml` and the hooks trusted once via `/hooks`. For usage limits and live session names, also install the **status line** integration in the same tab; your existing status line keeps working.
2. **Media:** press play in Spotify or Apple Music and allow Islet to control it when macOS asks.

<br>

## 🏗 Architecture

```mermaid
flowchart LR
    subgraph plugins["Plugins"]
        direction TB
        yours["<b>Your plugin</b>"]
        agents["Agents"]
        media["Media"]
        shelf["Shelf"]
    end
    core["<b>IsletCore</b><br/>plugin API · registry<br/>pill · settings store"]
    host["<b>IsletHost</b><br/>notch windows · animations<br/>settings · displays"]
    plugins -->|"IsletPlugin + PluginContext"| core
    host --> core
    style yours stroke-width:3px,stroke-dasharray:6 4
```

- **`Packages/IsletCore`** is the only thing a plugin imports: the `IsletPlugin` protocol, `PluginContext`, the registry and the pill types.
- **`Packages/IsletHost`** owns the notch windows, the settings window and the animations. It is the only package that uses private macOS frameworks, so your plugin never has to.
- **`Plugins/`** contains one Swift package per plugin, each depending only on `IsletCore`. They are linked into the app and listed in `AppDelegate.builtInPlugins` (`App/AppDelegate.swift`).

<br>

## 🛠 Development

The Xcode project is generated from `project.yml` with XcodeGen and is not checked in. Each package can be tested without Xcode:

```sh
swift test --package-path Packages/IsletCore
swift test --package-path Packages/IsletHost
swift test --package-path Plugins/AgentsPlugin
```

GitHub Actions builds the app and runs the tests of the whole `Islet` scheme on every pull request (`.github/workflows/ci.yml`).

<br>

## ❓ FAQ

<details>
<summary><b>How do I add my own plugin?</b></summary>
<br>
Plugins are Swift packages compiled into the app. Create one next to the built-in plugins, add it to <code>project.yml</code> and list it in <code>AppDelegate.builtInPlugins</code>, or let the <code>/new-plugin</code> skill in Claude Code do all three. The <a href="docs/plugins/getting-started.md">getting started guide</a> has the details.
</details>

<details>
<summary><b>Can I turn off the built-in plugins?</b></summary>
<br>
Yes. Every plugin can be switched off under <b>Settings › Plugins</b>. A disabled plugin is removed from the notch and stops running.
</details>

<details>
<summary><b>Does it work on a Mac without a notch?</b></summary>
<br>
Yes. On displays without a notch, Islet draws a virtual one at the top centre of the screen, and you can pick which displays show it.
</details>

<details>
<summary><b>Will the agent hooks slow down or break my agent?</b></summary>
<br>
No. The hook script only forwards each event to Islet on your machine. If Islet is not running, it gives up within a second and the agent carries on exactly as before. Only permission requests wait for your answer in the notch.
</details>

<details>
<summary><b>Why are my Claude usage limits not showing?</b></summary>
<br>
Claude Code only reports rate limits for Pro and Max plans, and only to its status line. Install the status line integration under <b>Settings › Agents</b> and send a message in Claude Code; the bar appears with the next update.
</details>

<br>

<div align="center">
<sub>Made for the notch you already have. What will you put in yours?</sub>
</div>
