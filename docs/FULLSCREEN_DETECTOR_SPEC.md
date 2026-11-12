# Behavioral Specification: Clean-Room Fullscreen Detector

## Purpose

Determine, for each currently connected display identified by its persistent display UUID, whether an application other than this app is currently occupying that display in fullscreen presentation or fullscreen media playback, using only public macOS frameworks (`AppKit`, `CoreGraphics`, `Foundation`).

This specification intentionally avoids private window-server / space APIs and third-party wrappers around them.

---

## Coordinate Systems

```
AppKit NSScreen coordinates (origin = primary display bottom-left, +Y upward)
+--------------------------------------------------+  y = primaryHeight
| [Primary Display frame]                          |
| safeAreaInsets.top (menu bar or notch cutout)    |
+--------------------------------------------------+  y = 0
x = 0

CoreGraphics CGWindowBounds coordinates (origin = primary display top-left, +Y downward)
x = 0, y = 0
+--------------------------------------------------+
| safeAreaInsets.top (menu bar or notch cutout)    |
| [CGWindowBounds rect]                            |
+--------------------------------------------------+  y = primaryHeight
```

Conversion from an AppKit display rectangle `(ax, ay, aw, ah)` into CoreGraphics display coordinates given `primaryHeight`:

- `cgX = ax`
- `cgY = primaryHeight - (ay + ah)`
- `cgWidth = aw`
- `cgHeight = ah`

Note: `primaryHeight` comes from the primary menu-bar display (the screen with `frame.origin == (0, 0)`, or `screens.first` if unavailable). Secondary displays positioned above, below, left, or right of the primary display keep positive or negative `cgX` / `cgY` accurately under this conversion.

---

## Inputs & Policies

### Policies

1. **`never`**: Detection is disabled. Every connected display evaluates to `false`.
2. **`always`**: Any qualifying fullscreen window on a display marks that display `true`.
3. **`nowPlayingOnly`**: A display evaluates to `true` only if a qualifying fullscreen window on that display belongs to the currently active media playback bundle identifier (matched case-insensitively). If no active media bundle identifier is available, `false` is returned for all displays.

### Per-Window Snapshot Fields

Each candidate window sampled via `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)` provides:

- `ownerPID`: owning process ID (`kCGWindowOwnerPID`)
- `ownerBundleIdentifier`: resolved via `NSRunningApplication(processIdentifier:)`
- `ownerName`: window owner name (`kCGWindowOwnerName`)
- `bounds`: CoreGraphics rectangle (`kCGWindowBounds`)
- `layer`: window layer (`kCGWindowLayer`)
- `isOnScreen`: boolean (`kCGWindowIsOnscreen`)

---

## Filtering & Fullscreen Classification Rules

For each display descriptor `(screenUUID, appKitFrame, safeAreaTopInset)`:

1. Convert `appKitFrame` into CoreGraphics rectangle `screenCG`.
2. Discard windows that fail any baseline pre-check:
   - `isOnScreen == false`
   - `layer != 0` (excludes desktop wallpaper, desktop icons, menu bar, dock, cursor overlays, and elevated panels such as this app's notch overlay)
   - `ownerPID == excludedPID` (this app's own PID)
   - System chrome owner bundle IDs (`com.apple.dock`, `com.apple.WindowManager`, `com.apple.controlcenter`, `com.apple.notificationcenterui`) or empty/non-positive window dimensions (`width <= 0` or `height <= 0`)
3. Check horizontal screen coverage against `screenCG` with `tolerance = 2.0 pt`:
   - `abs(window.minX - screenCG.minX) <= tolerance`
   - `abs(window.width - screenCG.width) <= tolerance`
   - (Stage Manager, Split View tiles, and standard floating windows fail width coverage and return `false`.)
4. Check vertical fullscreen coverage against `screenCG`:
   - Let `topAllowance = max(safeAreaTopInset, 40.0)` when the window starts below the screen top edge (covering macOS native fullscreen spaces under a notched display or visible menu bar) OR starts cleanly at `screenCG.minY`.
   - Specifically, both conditions must hold:
     - Top alignment: `window.minY >= screenCG.minY - tolerance` AND `window.minY <= screenCG.minY + topAllowance + tolerance`
     - Bottom alignment: `abs(window.maxY - screenCG.maxY) <= tolerance`
     - Minimum span: `window.height >= screenCG.height - topAllowance - tolerance`
5. If policy is `nowPlayingOnly`:
   - Require `activeMediaBundleIdentifier` to be non-empty and match `window.ownerBundleIdentifier` (case-insensitive).

If any window satisfies steps 2–5 for that display, `result[screenUUID] = true`; otherwise `result[screenUUID] = false`.

---

## State Transitions & Update Triggers

```
  [Workspace / Space / App / Screen / Preference Event]
                         |
                         v
            +-------------------------+
            | Collect Screen & Window |
            |   Public Snapshots      |
            +-------------------------+
                         |
                         v
            +-------------------------+
            | FullscreenDetectorEval  |  (Pure value-type evaluation)
            +-------------------------+
                         |
             did map change? (new != current)
               /                     \
             YES                      NO
             /                         \
            v                           v
   Publish fullscreenStatus       No-op (preserve idle)
```

Event observers attached on `MainActor`:

1. `NSWorkspace.shared.notificationCenter`:
   - `activeSpaceDidChangeNotification`
   - `didActivateApplicationNotification`
   - `didTerminateApplicationNotification`
2. `NotificationCenter.default`:
   - `NSApplication.didChangeScreenParametersNotification`
3. Preference & media source streams:
   - Fullscreen hide policy preference changes
   - Active media bundle identifier changes
4. Coalesced periodic reconciliation (`1.5s` timer): catches in-window browser HTML5 fullscreen transitions within an existing macOS Space that do not emit a Space switch notification, publishing updates only when the computed `[String: Bool]` dictionary actually changes.

---

## Edge Cases

- **No screens connected / primary height <= 0**: return `[:]`.
- **`CGWindowListCopyWindowInfo` returns `nil` or empty**: evaluate to all `false` for connected screens without crashing.
- **Partial/tiled or PIP windows**: fail horizontal (`width`) or vertical bottom/height tolerances -> `false`.
- **Two displays with identical dimensions side by side**: `abs(window.minX - screenCG.minX) <= 2.0` isolates the fullscreen window strictly to the display it covers.
- **Display unplug while fullscreen**: `result` contains only currently connected `NSScreen` UUIDs, clearing stale `true` flags automatically.
