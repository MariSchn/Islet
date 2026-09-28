# Collapsed pill and announcements

While the notch is closed, it can grow slightly sideways into a pill: an icon to the left of the notch and a short status to the right. Only one plugin's pill is visible at a time. Below the pill, a plugin can briefly show an announcement.

## Publishing a pill

Set `context.pillStatus` whenever your status changes, and set it to `nil` when there is nothing to show:

```swift
func increment() {
    let step: Int = context.settings.value(forKey: Self.stepKey) ?? 1
    count += step
    context.pillStatus = PillStatus(text: "Count \(count)", systemImage: "number", priority: .ambient)
}

func reset() {
    count = 0
    context.pillStatus = nil
}
```

Clearing the pill matters: a plugin that keeps a stale pill can keep the notch showing it and hide more relevant ones. The host clears `pillStatus` after `deactivate()`, and pills of disabled plugins are never shown.

`pillStatus` can be set from anywhere on the main actor: the plugin, a model callback or a view. It is cheap to set, but avoid republishing an identical value on every tick. `MediaController` only calls its `onPillChange` callback when the status changes.

## Layout

| Part | Source |
| --- | --- |
| Left of the notch (36 pt) | `systemImage` as an SF Symbol, or a small dot when it is `nil`. |
| Right of the notch | `ring` if set, otherwise `artwork` if set (a rounded thumbnail), otherwise `text`. Ring and artwork take a 36 point column; the ring is drawn at 18 points (`NotchGeometry.pillRingDiameter`) and the artwork at 20 points (`NotchGeometry.pillArtworkSide`). Text takes as much width as it needs, up to 220 points and at most the width of the navigation row's side column, and is truncated with "…". |
| Color | Orange for `.attention` and `.urgent`, otherwise `tint` if set, otherwise white. |

`text` is always used as the accessibility label, so fill it in even when you show a ring or artwork.

A ring shows proportions, for example how many agent sessions are in each state:

```swift
let ring = PillStatus.Ring(segments: [
    .init(value: 2, tint: Color.Resolved(red: 0.4, green: 0.65, blue: 1)),
    .init(value: 1, tint: Color.Resolved(red: 0.2, green: 0.78, blue: 0.35))
])
context.pillStatus = PillStatus(text: "3 jobs running", systemImage: "gearshape.2", priority: .info, ring: ring)
```

Each segment's arc is proportional to its `value`. Segments with a value of 0 are skipped, and a ring without positive values is drawn as a faint empty circle. Colors are `Color.Resolved` so that `PillStatus` stays `Sendable`.

## Priorities

`PillStatus.Priority`, from lowest to highest:

| Priority | Use for | Example |
| --- | --- | --- |
| `.ambient` | Background information that is nice to see. | Music playing, an agent that finished. |
| `.info` | Something in progress the user started. This is the default. | An agent working. |
| `.attention` | Something that needs the user. Always shown, in orange. | An agent waiting for a permission decision. |
| `.urgent` | Like `.attention`, but wins over it. | |

Use `.attention` and `.urgent` sparingly: they override the user's choice of which pill to show.

## Which plugin's pill is shown

The host considers every enabled plugin with a non-nil `pillStatus`:

1. If any pill has priority `.attention` or higher, the one with the highest priority is shown. On a tie, the plugin registered first wins.
2. Otherwise the user's choice under Settings › Notch › Collapsed Pill (`PillSelection`) decides:
   - **Last viewed plugin** (`lastViewed`, the default): the plugin that was open when the notch collapsed. If it has no pill, the most important pill is shown instead, and the notch keeps showing that plugin until its pill becomes `nil` or the notch is opened again.
   - **Latest activity** (`latestActivity`): the plugin whose activity started most recently.
   - **Most important** (`mostImportant`): the pill with the highest priority.

"Activity starts" when a plugin's pill goes from `nil` to a value, or when its priority goes up. Changing the text or lowering the priority does not count as new activity. So if you want a plugin to come back to the front under "Latest activity", clear the pill when the activity ends and set it again when a new one starts.

When the user opens the notch, the host selects the plugin whose pill was shown, so the expanded notch continues where the pill left off.

## Announcements

An announcement is a one-line message shown below the pill for 4 seconds, for events the user should notice in passing:

```swift
if count >= 100 {
    context.announce(PillAnnouncement(text: "Counter reached 100", systemImage: "flag.checkered", priority: .info))
}
```

- Announcements appear only while the notch is closed. One made while the notch is open is dropped, not queued, and opening the notch dismisses the current one.
- Each announcement is shown once, identified by its `id`. `PillAnnouncement.init` generates a new `id` by default, so create a new value for each event.
- If several plugins announce at the same time, the highest `priority` wins. A new announcement does not replace one of higher priority that is still visible.
- `systemImage` is tinted with `tint` (white when `nil`); the text is white.
- A plugin holds only its latest announcement. The host clears it when the plugin is disabled.

Announcements are shown in addition to the pill, not instead of it. Avoid announcing something the user just did themselves, and consider making announcements optional in your settings, as `AgentsPlugin` does.
