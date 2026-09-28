# Sizing and the notch

When the notch expands, it grows into a black shape with two parts:

```
┌──────────────┬────────┬──────────────┐
│ plugin tabs  │ notch  │   settings   │  navigation row (height of the menu bar/notch)
├──────────────┴────────┴──────────────┤
│                                      │
│            plugin screen             │  contentSize
│                                      │
└──────────────────────────────────────┘
```

Your plugin controls the lower part through `context.contentSize`. The host derives everything else from it: the shape is as wide as the content (at least as wide as the notch) and as tall as the navigation row plus the content height.

## Setting contentSize

```swift
public func activate() async throws {
    context.contentSize = CGSize(width: 360, height: 120)
}
```

- The size is in points at the Default notch size, and it includes the host's padding: your view is inset by 12 points on every side. A `contentSize` of 360 × 120 leaves 336 × 96 points for your layout.
- `nil` means the default size, 520 × 220 (`NotchGeometry.defaultContentSize`).
- Set it before the notch first opens, in `init` or `activate()`, so it doesn't open at the default size and then jump.
- Change it whenever your content changes. The resize is animated with the same animation as expanding the notch. The simplest way is to derive it from your model, so it follows every change on its own:

  ```swift
  context.derive(\.contentSize) { [store] in Self.contentSize(forItemCount: store.items.count) }
  ```
- While the notch is open, the host lays out the plugins on either side of the selected one using their own `contentSize`, and animates the size when the user switches plugins.

## Clamping

The host clamps the requested size to the screen (`NotchGeometry.contentSize(for:)`):

| | Minimum | Maximum |
| --- | --- | --- |
| Width | 240, or the notch width + 160 if that is larger | 960, or the screen width − 120 if that is smaller |
| Height | 80 | 640, or half the screen height if that is smaller |

When a size is clamped, your view gets the clamped area, so prefer flexible layouts (`frame(maxWidth: .infinity, maxHeight: .infinity)`, `ScrollView`) over hard-coded frames that assume the exact size.

## Notch size setting

Settings › Notch › Size scales the whole notch: Small 0.85, Default 1, Large 1.2, Extra Large 1.4 (`NotchSize.scale`). The host lays out your screen at the size you requested and scales it with `scaleEffect`, so don't multiply by the scale yourself. Clamping is applied after scaling.

## Computing the size from state

When the height depends on your content (rows, expanded sections), derive it from the same constants the views use and keep both in one place. `AgentsPlugin` does this with a static function:

```swift
static func contentSize(for sessions: [AgentSession], expanded: Set<String>, showsUsage: Bool, historyLength: Int) -> CGSize
```

The plugin passes it to `context.derive(\.contentSize)`, so it is recomputed whenever the sessions, the expanded rows or the display settings change, and the views use the same `rowHeight`, `rowSpacing` and padding constants. A static function like this is easy to cover with unit tests (see [Testing](testing.md)).

The other built-in plugins follow the same pattern:

- `ShelfPlugin.contentSize(forItemCount:)` keeps a fixed height and grows the width with the number of files, between a minimum and a maximum after which the list scrolls. The plugin derives it from `store.items.count`.
- `MediaPlugin` keeps a fixed size while playing, so pausing or changing tracks doesn't move the notch, and grows the height by one row per playlist while the playlist browser is open.

Use `@Environment(\.notchAnimation)` for animations inside your screen that go with a size change (see [API reference](api-reference.md#environment-notchanimation)).

## Width and the collapsed pill

The width of the side columns of the navigation row, `(expanded width − notch width) / 2`, also limits how wide the text of the collapsed pill can be (see [Collapsed pill](collapsed-pill.md#layout)). The width used for that is the one of the selected plugin. A very narrow plugin makes the pill text of every plugin truncate earlier.
