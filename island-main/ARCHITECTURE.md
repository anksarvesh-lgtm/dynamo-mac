# Architecture

```
System event / app ──▶ Provider ──ActivityUpdate──▶ ActivityManager ──observed by──▶ IslandViewModel ──▶ IslandRootView (one window)
                                                         │
                                                         └──IslandEvent──▶ EventBus ──▶ AutomationEngine
User / search / AI ──IslandCommand / AppAction──▶ CommandRouter (+ PermissionPolicy) ──▶ services (media, timers, downloads…)
```

## Rules

- **Providers only submit `ActivityUpdate`s** (`upsert`, `remove`, `complete`). They never touch the window or views.
- **`ActivityManager`** (IslandCore) is the single source of truth. It validates and sanitises input (malformed events are rejected, not crashed on), orders activities deterministically, expires transient ones with a single scheduled wake-up, and publishes lifecycle events.
- **`IslandPresentation`** is a pure state machine (`idle / compact / expanded / search`). Timing such as hover intent and collapse delays lives in `IslandViewModel`.
- **`IslandMetrics`** derives every size from the detected notch. Nothing is hard-coded to a screen.
- **`IslandWindowController`** owns the single non-activating `NSPanel`. The window has a fixed size per display, so animations never fight a resizing window. Mouse pass-through is toggled from the computed hit rect.
- **Everything actionable is typed.** Views send `IslandCommand`. Natural language, from users or AI, is parsed into `AppAction` and checked by `PermissionPolicy`. AI providers are text-in/text-out with no system tools.

## Layout

```
Sources/IslandCore/          pure, testable logic (no AppKit UI)
  Core/ActivityState         Activity + content models
  Core/ActivityManager       manager, ordering, validation
  Core/EventBus              pub/sub for automation & diagnostics
  Core/DisplayManager        notch geometry + display selection
  Core/Presentation          state machine + metrics
  Core/CommandRouter         IslandCommand, AppAction, ActionRouter
  Core/Permissions           SafetyLevel, PermissionPolicy
  Activities/                pure provider logic (media selection, battery transitions)
  Search/                    SearchEngine, SearchRouter, ranking
  Services/Web|AI|Keychain   HTTP, web providers, AI providers, research, Keychain
  Automation/                WHEN / IF / THEN rules
  Settings/                  persisted preferences
Sources/Island/              the app
  App/                       entry, composition root, status item, self-test
  Core/                      NSScreen → geometry, hotkey, accessibility, router
  Island/Window|Views|Animation|Glass
  Activities/<kind>/         provider + views per activity
  Services/Media/            MediaService + Music/Spotify/VLC/Browser/System providers
  Settings/  Debug/
Tests/IslandCoreTests/       dependency-free test runner
```

## Failure isolation

Every external integration is independent and started or stopped from settings. AppleScript runs out of process (`osascript`) with a hard timeout, so a hung media app can't block Island. Each search provider has its own timeout, and its failure only marks its own section. Every keystroke cancels the previous search. Network calls retry transient errors and surface 429s as rate limits.
