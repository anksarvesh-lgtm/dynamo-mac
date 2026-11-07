# ILoveNotch implementation plan

Status: shipped. 1.0.0 is on GitHub Releases (25 September 2026); the Mac App Store edition is in review  
Target: original, open-source macOS notch utility  
Minimum system: macOS 14.6  
Primary architecture: Apple silicon, with Universal 2 support evaluated for v1

## 1. Product direction

ILoveNotch will recreate the useful product category with original code, design,
copy, icons, motion, and assets. The goal is functional parity followed by a
better experience, not a branded or pixel-for-pixel copy of another product.

Core principles:

- Native SwiftUI and AppKit; no Electron or web view shell.
- Local-first and usable without an account or license server.
- No device fingerprinting or analytics by default.
- Event-driven system integrations instead of polling loops.
- Features consume resources only while enabled or visible.
- Public macOS APIs first; unstable integrations remain optional adapters.
- Performance, accessibility, and failure recovery are release requirements.
- Original or permissively licensed code and assets only.
- GitHub Releases are the primary distribution channel, with the full feature
  set. A sandboxed Mac App Store edition with a smaller feature set follows it
  (see [§10](#app-store-edition)).

The product is named ILoveNotch. The code keeps OpenNotch for its modules,
targets, and bundle ID (`cafe.opennotch.app`), so settings and permissions carry
over.

## 2. Current prototype

The Phase-0 prototype already provides:

- A Swift 6 package targeting macOS 14.
- Public notch geometry through `NSScreen` safe-area APIs.
- A borderless, transparent `NSPanel`.
- Hover-driven open and close behavior.
- Placeholder Media, Tray, Tasks, and Notes tabs.
- An MIT license.

Before adding product features, correct these limitations:

- The project is one executable target with no proper app target or test target.
- Only one screen is chosen at launch.
- Presentation state is represented by one `isOpen` Boolean.
- AppKit animates the physical window frame while SwiftUI applies a separate
  spring, creating two animation owners.
- The manual bundle script is not a signing, entitlement, or release pipeline.
- The README promises Apple Notes synchronization through Apple Events, which
  is brittle and permission-heavy.
- There is no settings surface, permission coordinator, CI, or performance
  baseline.

## 3. Target architecture

Runtime flow:

```text
macOS callbacks
    -> system adapters
    -> typed event hub
    -> finite-state lifecycle reducer
    -> feature activation policy
    -> fixed NSPanel and SwiftUI notch surface
```

Recommended project shape:

```text
ILoveNotch/
├── App/
│   ├── ILoveNotchApp
│   ├── AppDelegate
│   └── Resources
├── Packages/
│   ├── NotchCore
│   │   ├── StateMachine
│   │   ├── FeatureRegistry
│   │   └── DomainModels
│   ├── NotchSurface
│   │   ├── PanelCoordinator
│   │   ├── NotchShape
│   │   ├── HitTesting
│   │   └── MotionSystem
│   ├── SystemAdapters
│   │   ├── Display
│   │   ├── Media
│   │   ├── Audio
│   │   ├── Calendar
│   │   ├── Camera
│   │   └── Sharing
│   ├── Features
│   │   ├── Media
│   │   ├── Shelf
│   │   ├── Calendar
│   │   ├── Notes
│   │   ├── Mirror
│   │   └── HUD
│   └── Diagnostics
├── Tests/
├── UITests/
├── PerformanceTests/
├── docs/
└── project.yml
```

Start with five or six targets. Do not build a general plug-in platform before
v1; introduce new boundaries only when a feature or test requires them.

### 3.1 Presentation state

Replace `isOpen` with explicit states:

```swift
enum NotchPresentationState {
    case hidden
    case compact
    case hoverArmed
    case expanded(tab: FeatureID)
    case pinned(tab: FeatureID)
    case focused(tab: FeatureID)
    case transient(Activity)
    case suspended
}
```

Pointer, click, scroll, drag, media, full-screen, display, sleep, and permission
events go through one reducer. The reducer returns a new state plus explicit
effects, preventing conflicting Boolean combinations and race conditions.

### 3.2 Window and display behavior

- Use one fixed-size transparent panel per enabled display.
- Size the panel for the maximum expanded surface.
- Animate the internal notch shape, not the physical window frame.
- Return `nil` during hit testing outside the visible shape.
- Keep view-only states non-activating.
- Enter a controlled key/focus state only for text entry.
- Listen for screen-parameter changes and rebuild display geometry safely.
- Support primary-only and all-display settings.
- Provide a floating pill presentation on notchless displays.
- Keep a menu-bar fallback for Settings, permissions, reset, and Quit.

## 4. Motion and animation system

The reference bundle exposes native spring and AppKit animations, a display
link, Lottie, fluid gradients, blur/scale effects, custom wave and audio
spectrograph views, Perlin noise, vibrating circles, and looping videos. These
are static observations; the unpublished runtime behavior and exact parameters
are unknown.

ILoveNotch should use one named motion system:

| Interaction         | Technique                             | Initial timing | Resource rule                  |
| ------------------- | ------------------------------------- | -------------: | ------------------------------ |
| Compact to expanded | One animatable shape spring           |        ~320 ms | Never resize the panel         |
| Expanded to compact | Faster low-bounce spring              |     220–250 ms | Cancel hidden feature work     |
| Hover feedback      | Opacity/highlight                     |     100–140 ms | No display link                |
| Tab selection       | Moving capsule and content transition |     160–180 ms | Do not construct inactive tabs |
| Artwork change      | Crossfade                             |        ~160 ms | Precompute colors off-main     |
| File drag entry     | Interactive spring and rim glow       |        ~260 ms | Stop immediately on drag exit  |
| Live activity       | Phase/keyframe sequence               | Event-specific | One-shot only                  |
| Icon feedback       | SF Symbol effect                      | Event-specific | Discrete effects by default    |
| Audio visualizer    | Canvas or Metal-backed rendering      | Maximum 30 FPS | Only visible while media plays |
| Reduce Motion       | Direct shape change and crossfade     |     100–150 ms | No bounce, zoom, or parallax   |

Guidelines:

- Use one continuously rounded `Animatable` notch shape so the compact and
  expanded forms read as one object changing shape.
- Use SF Symbols for system actions and original custom symbols where the
  product needs distinctive identity.
- Use Lottie only for optional onboarding, changelog, or mascot sequences.
- Avoid per-frame blur, wallpaper sampling, and dominant-color calculation.
- Pause visualizers, gradients, and animated images when hidden or occluded.
- Respect Reduce Motion, Reduce Transparency, increased contrast, VoiceOver,
  keyboard navigation, and right-to-left layouts.

## 5. Comparison

Static bundle observations do not assert how the commercial app's unpublished
source is organized internally.

| Area              | Reference observation                                   | Current prototype                          | ILoveNotch target                                      |
| ----------------- | ------------------------------------------------------- | ------------------------------------------ | ----------------------------------------------------- |
| Technology        | Native SwiftUI/AppKit                                   | Native SwiftUI/AppKit                      | Keep native                                           |
| Architecture      | Multiple managers in one executable                     | One executable target                      | Core, surface, features, adapters, diagnostics        |
| State             | Multiple window/service concepts                        | One Boolean                                | Explicit reducer/state machine                        |
| Window animation  | AppKit/Core Animation and display-link components       | AppKit frame animation plus SwiftUI spring | Fixed panel and one shape animation owner             |
| Decorative motion | Lottie, gradients, noise, wave, spectrograph            | Simple spring and opacity                  | Native motion tokens and optional one-shot Lottie     |
| Background work   | Timer, polling, and display-link components are present | No polling yet                             | System callbacks and cancellable deadline timers only |
| Media             | MediaRemote and app scripting                           | Placeholder                                | Isolated helper with fallback and health checks       |
| Shelf             | Tray and AirDrop                                        | Placeholder                                | Native drag, persistence, Quick Look, AirDrop         |
| Calendar          | Calendar permissions and managers                       | Planned                                    | EventKit callbacks and bounded queries                |
| Camera            | Camera and microphone purpose strings                   | Planned                                    | Camera only unless audio is genuinely required        |
| Notes             | Internal notes                                          | Apple Notes automation proposed            | Local Markdown/SwiftData, optional CloudKit later     |
| HUDs              | Volume and brightness replacement                       | Planned                                    | CoreAudio public path; brightness experimental        |
| Privacy           | License verification and device fields                  | No backend                                 | Local-only and zero idle networking                   |
| Testing           | Unknown                                                 | Geometry assertion                         | Unit, UI, snapshot, performance, and soak tests       |
| Distribution      | Signed vendor releases                                  | Manual unsigned bundle                     | Developer ID, hardened runtime, notarized DMG         |

## 6. Feature and API risk

| Feature                     | Preferred implementation                               |        Risk | Planned release |
| --------------------------- | ------------------------------------------------------ | ----------: | --------------- |
| Notch shell                 | AppKit/SwiftUI and public screen geometry              |         Low | v0.1            |
| Media                       | Isolated `mediaremote-adapter` helper                  | Medium/high | v0.2            |
| File shelf/AirDrop          | Native dragging, bookmarks, `NSSharingService`         |         Low | v0.2            |
| Calendar/reminders          | EventKit                                               |         Low | v0.3            |
| Notes                       | Local Markdown or SwiftData                            |         Low | v0.3            |
| Shortcuts                   | `shortcuts://` first; Apple Events only when necessary |      Medium | v0.3            |
| Camera mirror               | AVFoundation                                           |         Low | v0.3            |
| Volume indicator            | CoreAudio property listener                            |         Low | v0.3            |
| Volume HUD interception     | Accessibility/event tap                                |      Medium | v0.4            |
| Brightness control          | Replaceable compatibility adapter                      |        High | Experimental    |
| Bluetooth accessory battery | Device-specific adapter                                |        High | Experimental    |
| General notification mirror | No clean general public API                            |   Very high | Deferred        |
| AI subscription usage       | OpenUsage's provider runtime (MIT), opt-in providers   |      Medium | Phase 8         |

Candidate dependencies:

- Compare the in-house panel engine against DynamicNotchKit in a measured spike.
- Use `mediaremote-adapter` behind a process/protocol boundary.
- Use Sparkle 2 for signed update feeds.
- Prefer OSLog and OSSignposter over a third-party logging SDK.
- Keep Lottie out of the always-visible path.
- Track every dependency and license in `THIRD_PARTY_NOTICES`.

Do not copy code from GPL projects while distributing ILoveNotch under MIT. A
deliberate move to GPL is a separate product decision.

## 7. Delivery phases

### Phase 0: clean repository and governance — 2–3 days

- Initialize Git and preserve the current scaffold as `prototype-0`.
- Confirm the final name later.
- Add contribution, security, privacy, and third-party license documents.
- Ignore app bundles, extracted binaries, disassembly, signing data, and secrets.
- Create a behavior-only parity checklist.
- Define release versioning and pull-request conventions.

Exit: the repository contains only original or permissively licensed material.

### Phase 1: build system and core — about 1 week

- Add a real Xcode app target generated from `project.yml`.
- Keep the core packages independently testable with SwiftPM.
- Enable Swift 6 strict concurrency.
- Implement the state reducer and feature lifecycle.
- Introduce typed logging and signposted operations.
- Add unit and performance test targets.
- Add CI for builds, tests, formatting, and license checks.

Exit: repeatable Debug and Release builds with automated tests.

### Phase 2: production notch surface

- Implement the fixed panel and animatable notch shape.
- Add compact, expanded, pinned, focused, transient, and suspended states.
- Add pointer hysteresis, click-away, Escape, scrolling, and drag behavior.
- Add multi-display and notchless-display handling.
- Add settings/menu-bar recovery.
- Add accessibility variants.

Exit: 1,000 open/close transitions without state corruption or memory growth.

### Phase 3: useful core

- Add media information and playback controls.
- Add bounded artwork caching.
- Add file drop, persistent shelf, drag-out, Quick Look, and AirDrop.
- Add explicit unavailable/permission-denied UI.

Exit: a useful v0.2 build with independently functioning Media and Shelf.

### Phase 4: productivity features

- Calendar and today view.
- Reminders-backed tasks.
- Local notes.
- Shortcut launcher.
- Timer and stopwatch.
- Feature-specific settings.

Exit: every module starts, suspends, resumes, and releases resources correctly.

### Phase 5: camera and system integrations

- Lazy camera mirror.
- CoreAudio volume listener.
- Battery and charging activity.
- Optional HUD replacement.
- Experimental brightness and Bluetooth adapters.
- Feature-scoped permission onboarding.

Exit: capture sessions, audio work, helpers, and event taps stop when hidden.

Done: the Mirror tab (off by default; the camera runs only while it's open),
volume, battery, and Bluetooth accessory activities from Core Audio and IOKit
callbacks, and an opt-in volume-key event tap that replaces the macOS volume
display. Brightness stays with macOS, since Apple silicon has no public API to
read or set it.

### Phase 6: visual and motion polish

- Finalize motion tokens.
- Create original icon and brand assets: the exact files are listed in
  [brand assets](../brand-assets.md).
- Add symbol effects, haptics, themes, and optional original mascot.
- Complete accessibility and localization infrastructure.

Already done: open and close animation styles, tab motion, the media redesign
with an audio-reactive waveform, and Reduce Motion, Reduce Transparency, and
Increase Contrast support. Waiting on design: the final name, app icon, menu bar
icon, logo, and DMG and store artwork.

### Phase 7: hardening and public beta

- Run long-duration idle and active tests.
- Test sleep/wake, display changes, full screen, and permission changes.
- Test helper crashes and adapter failure recovery.
- Produce signed beta builds and test upgrade/rollback behavior.

A useful beta is realistic in 1-2 days. Broad parity and a hardened release
should be planned as approximately 3-4 days of focused work.

### Phase 8: AI usage in the notch

Bring [OpenUsage](https://github.com/robinebers/openusage) into the notch: how
much of each AI coding subscription is used, with session and weekly limits,
credits, spend, and reset countdowns, as a native Usage tab with better icons
and UI than a menu bar popover.

- **Source.** OpenUsage is MIT-licensed Swift (SwiftPM, Swift 6 strict
  concurrency, macOS 15+). Absorb its provider runtime (auth store → usage
  client → mapper → snapshot) for Antigravity, Claude, Codex, Copilot, Cursor,
  Devin, Grok, Ollama, OpenCode, OpenRouter, and Z.ai into a `NotchUsage`
  module, keep its license notice in `THIRD_PARTY_NOTICES.md`, and credit it in
  the README.
- **Brand.** OpenUsage's trademark policy covers its name and logo: the tab
  gets our own name, UI, and icon, never "OpenUsage" or its logo, and the README
  says the usage code is adapted from OpenUsage, not that it is OpenUsage.
- **Provider icons.** Provider logos come from [theSVG](https://thesvg.org)
  (`glincker/thesvg`, MIT; `@thesvg/icons` on npm), using the mono variant in
  the notch and color where a provider is selected, bundled as SVG in the asset
  catalog. The logos stay their owners' trademarks and only identify each
  provider; `THIRD_PARTY_NOTICES.md` says so.
- **UI.** A Usage tab with one row per provider (logo, used/limit meters, reset
  countdown, pace), a detail view per provider, a live activity when a limit is
  close or resets, and optional usage rings in the closed notch's wings.
- **Privacy.** Leave out OpenUsage's anonymous summaries, PostHog crash
  reporting, and Sparkle setup. Each provider is off until turned on, reads only
  credentials already on the Mac, and talks only to that provider. Refresh on
  opening the tab, plus an optional background interval; that interval is the
  one exception to "no network while idle", so PRIVACY.md must list it.
- **Distribution.** Reading other apps' credentials doesn't fit the App Sandbox,
  so the Usage tab ships in the GitHub (Developer ID) build only.
- **Minimum macOS.** OpenUsage needs macOS 15. Backport to 14.6 or raise the
  minimum for this module.

Exit: parity with OpenUsage's providers and metrics, per-provider opt-in, no
refresh while hidden unless enabled, and mapper tests on recorded fixtures.

Done: the AI Usage tab in the GitHub build. OpenUsage's providers, pricing, and
services are adapted at commit 4ce7887 into `Sources/NotchUsage/OpenUsage`,
with its own cache folder and User-Agent. Its reset-credit claim is left out,
and so is Antigravity's Google token renewal, which embeds Antigravity's OAuth
client secret; an expired Antigravity sign-in asks you to open the app. The rest
is rebuilt:

- One tile per provider: its headline limit as a ring, up to three limits as
  bars, the reset countdown, and pace ("Plenty left", "Runs out in 28m").
  Limits turn amber at 80% and red at 95%.
- A detail view with every limit, spend chips for today, yesterday, and the
  last 30 days, and the daily trend as a Swift Charts bar chart. With one
  provider on, the detail is the whole tab.
- Onboarding that offers the tools signed in on this Mac.
- Live activities when a limit passes 80% or 95%, or resets, while the tab is
  off screen.
- A settings page with per-provider toggles and an optional background interval.

theSVG's mono logos ship as SwiftPM resources, drawn in each provider's color.
The providers run on macOS 14.6, so the minimum didn't change. 64 of
OpenUsage's test files, 752 tests on its fixtures, run in the `OpenUsageTests`
target. The closed-notch rings were left out, because the closed notch blends
into the camera housing by design; the activities cover the glance.

## 8. Performance gates

Measure on a named reference Mac with a fixed OS version and test dataset.

| Scenario                            |                        Acceptance target |
| ----------------------------------- | ---------------------------------------: |
| Collapsed idle CPU                  | Median <= 0.3%, p95 <= 1% after settling |
| Idle recurring wakeups              |                             Ideally zero |
| Warm collapsed memory               |                         Target <= 120 MB |
| Eight-hour memory drift             |          <= 10 MB after caches stabilize |
| 1,000 open/close cycles             |              No persistent memory growth |
| Static expanded CPU                 |          <= 2% without camera/visualizer |
| Animation hitch rate                |                               <= 10 ms/s |
| Main-thread work during interaction |               Preferably < 5 ms per turn |
| Input-to-visible response           |                                 < 150 ms |
| Hidden camera/visualizer work       |                                     Zero |
| Idle network requests               |      Zero except an enabled update check |

Use Instruments Time Profiler, Allocations, Leaks, SwiftUI, Animation Hitches,
File Activity, and Energy Log. Add `XCTCPUMetric`, `XCTMemoryMetric`,
`XCTHitchMetric`, and `XCTOSSignpostMetric` baselines to performance tests.

## 9. QA matrix

Operating systems:

- macOS 14.6
- macOS 15.6
- macOS 26 latest stable update
- macOS 27 latest stable update

Hardware and display conditions:

- Apple silicon built-in notch.
- Notchless external display.
- Single display, multiple displays, and clamshell mode.
- Hot-plugging and display resolution/scaling changes.
- Intel hardware on older supported macOS if Universal 2 remains a v1 goal.

Behavioral coverage:

- Apple Music, Spotify, browser media, and QuickTime.
- Permissions granted, denied, and revoked while the app is running.
- Sleep/wake, lock/unlock, and full-screen applications.
- Battery and charger changes.
- Camera removal or failure while the mirror is open.
- Deleted, moved, and corrupt shelf files.
- Media helper crash and restart.
- Light/dark mode, high contrast, Reduce Motion, VoiceOver, keyboard-only use,
  and right-to-left layout.

## 10. Release pipeline

GitHub Releases are the official installation and update channel from the first
public beta onward. Users should be able to open the repository's Releases
page, download the latest DMG, drag ILoveNotch into Applications, and launch it
normally. No public release will wait for, or depend on, Mac App Store approval.

The project owner has confirmed that a paid Apple Developer account is
available. We will use it for Developer ID signing and Apple notarization, with
Hardened Runtime enabled, so GitHub downloads open normally without avoidable
Gatekeeper warnings. The app remains open source and free to build locally even
though the downloadable release is signed with the project's Developer ID.

Release steps:

1. Build and test each pull request on GitHub Actions.
2. Create a version tag such as `v0.2.0` or `v1.0.0`.
3. Archive a Universal 2 or arm64 Release configuration according to the
   supported-hardware policy.
4. Sign the app and every helper executable with Developer ID.
5. Enable Hardened Runtime and only the required entitlements.
6. Submit the signed artifact using `notarytool`.
7. Staple the notarization ticket to the app and DMG.
8. Package a polished DMG containing ILoveNotch and an Applications shortcut.
9. Verify the DMG on a clean Mac user account before publishing it.
10. Generate SHA-256 checksums, an SBOM, and a third-party license inventory.
11. Publish the DMG, checksum, release notes, and source archives on GitHub
    Releases on the same day that the version is declared public.
12. Sign and publish the Sparkle appcast so installed builds can update from
    GitHub Releases.
13. Test upgrades, skipped versions, interrupted downloads, and rollback.
14. Add a Homebrew cask as an optional second installation route. Done with
    1.0.0: `brew install --cask niyamvora/tap/ilovenotch`.

The README download instructions should always point to the latest GitHub
Release and clearly distinguish:

- Signed and notarized DMG: recommended for most users.
- Source build: for developers and contributors with Xcode.
- Nightly build: optional, clearly marked as unsupported and potentially
  unsigned.

### App Store edition

The project owner has asked for a Mac App Store release, reconsidering the
earlier decision to keep it out of v1. The App Store requires the App Sandbox
and forbids private APIs and self-updating, so the App Store build is a separate
edition of the same code with a smaller feature set, and the GitHub build stays
the full one:

| Feature | GitHub build | App Store edition |
| ------- | ------------ | ----------------- |
| Notch, tabs, click-away, launch at login | Yes | Yes |
| Media from any app, with controls | Yes, through the mediaremote-adapter helper | No: the helper reaches a private framework. Music and Spotify's public notifications show what's playing, and Music can be controlled through its scripting access group. |
| Audio-reactive waveform | Yes | If Core Audio taps work in the sandbox (to verify); otherwise the stand-in motion |
| Shelf | Yes | Yes, with security-scoped bookmarks so files survive relaunch |
| Calendar, Tasks, Notes, Timer | Yes | Yes |
| Shortcuts | Lists and runs them in the background | Runs them by name through `shortcuts://`, which opens Shortcuts |
| Camera mirror, volume and battery activities | Yes | Yes |
| Volume display replacement (event tap) | Opt-in | No: needs Accessibility, unavailable to sandboxed apps |
| Bluetooth accessory battery | Experimental | No |
| AI usage (Phase 8) | Yes | No: reads other apps' credentials |
| Updates | Update ILoveNotch (local builds) or Sparkle | The App Store |

The edition is the `OpenNotchAppStore` target (scheme `OpenNotch App Store`): the
same sources with an `APP_STORE` compile-time flag, sandbox entitlements
(`App/AppStore/OpenNotch.entitlements`), and none of the helper, Sparkle, or the
local updater. Sandboxed, the shelf keeps security-scoped bookmarks. Signing,
the upload to App Store Connect, and TestFlight use the team's App Store Connect
API key with cloud-managed certificates (`make app-store`). Creating the app
record and answering App Privacy are one-time steps in the App Store Connect
website; see [releasing](../releasing.md#the-app-store-edition).

## 11. First development sprint

Before implementing another feature:

1. Preserve the prototype in Git.
2. Introduce the presentation state machine.
3. Replace panel resizing with fixed-panel shape animation.
4. Add pointer hysteresis and shape-based hit testing.
5. Add display-change handling.
6. Add a menu-bar recovery and settings entry.
7. Replace Apple Notes automation with local notes.
8. Add unit and performance test targets.
9. Record initial CPU, memory, wakeup, and hitch baselines.
10. Compare the in-house surface and DynamicNotchKit using the same tests.

## References

- [Architecture diagram](architecture.html)
- [Architecture source](architecture.json)
- [Apple: energy-efficient timer use](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html)
- [Apple: SwiftUI animation timing and movement](https://developer.apple.com/documentation/swiftui/controlling-the-timing-and-movements-of-your-animations)
- [Apple: Reduce Motion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion)
- [Apple: XCTest performance metrics](https://developer.apple.com/documentation/xctest/performance-tests)
- [Apple: notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit)
- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
