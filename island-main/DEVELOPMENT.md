# Development

Requirements: macOS 14+, Xcode or just the Command Line Tools (Swift 6.x).

```sh
scripts/build.sh [debug|release] [arm64|x86_64] [--tests]
scripts/test.sh                 # IslandCoreTests + `Island --self-test`
scripts/run.sh [--demo]         # bundle + launch a debug Island.app
scripts/island-debug.sh expand  # drive a running DEBUG build: expand|collapse|search|next|music|timer|download|recording|critical|battery|clear|dump|query:<text>
```

The build uses `swiftc` directly (see `scripts/env.sh`). `env.sh` picks an SDK that the installed compiler can actually compile against, which works around partially updated Command Line Tools. `Package.swift` is provided for Xcode / SwiftPM users.

**Tests.** `Tests/IslandCoreTests` uses a tiny built-in harness (`TestKit.swift`), so it runs without XCTest or swift-testing. Register new suites in `main.swift`. `Island --self-test` launches the real window and view model headlessly and checks launch, compact, hover, expansion, interaction, collapse, priority, switching, search and malformed input.

**QA.**
- `scripts/qa/e2e.sh`: an end-to-end suite of 38 checks using real mouse and keyboard events. It covers hover, Escape, ⌥Space search typing and Return, click-outside, bubbles, buttons, and the settings toggles. It needs Accessibility permission for your terminal, and it moves your pointer, so don't touch the Mac while it runs.
- `scripts/island-debug.sh stress:<seed>`: 400 randomized operations against the real controller with invariant checks. Results go to `$TMPDIR/island-stress.txt`.
- `scripts/island-debug.sh frames:<seconds>`: records frame pacing during animations to `$TMPDIR/island-frames.txt`.
- `scripts/qa/press.sh "<VoiceOver label>"`: clicks any Island control by its accessibility label.

**Debug tools.** Menu bar → Debug Panel shows live state, the activity queue, display, window frame, CPU, memory, FPS and the event log, plus buttons for test activities. Settings › Advanced › Performance overlay adds a HUD. Set `ISLAND_TRACE=1` to log mode transitions in DEBUG builds.

**Adding an activity.**
1. Add a content case in `ActivityContent.swift`.
2. Add a provider under `Sources/Island/Activities/<Kind>/` that submits `ActivityUpdate`s.
3. Add views and a case in `ActivityPresentation.swift`.
4. Start and stop it in `AppEnvironment.syncProviders()`.

**Releasing.** Push a tag `vX.Y.Z`. `.github/workflows/release.yml` tests, builds a universal app, packages zip and dmg, and publishes a GitHub Release.
