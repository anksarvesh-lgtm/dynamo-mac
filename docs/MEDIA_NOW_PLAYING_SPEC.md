# LiquidDynamo — Media & Now Playing Chain Behavioral Specification (Step 3)

## 1. Purpose & Design Constraints
- Provide reliable, App-Sandbox-compatible media playback state detection, artwork presentation, and transport control inside LiquidDynamo without depending on unsandboxed subprocess workarounds or private framework crashes.
- Remove placeholder novelty metadata so idle or unavailable states report empty/inactive playback honestly and allow notch/island surfaces to render clean idle UI.
- Support automatic multi-player selection across macOS media apps alongside dedicated per-player modes and explicit opt-in web browser detection.

## 2. Sandbox & OS Backend Eligibility
1. **Runtime Environment Evaluation**:
   - Inspect whether the application is running inside App Sandbox (`APP_SANDBOX_CONTAINER_ID` present in process environment) and read the current macOS major/minor OS version (`ProcessInfo.processInfo.operatingSystemVersion`).
2. **Backend Classification**:
   - **Automatic Sandbox-Safe (`auto`)**: Default controller whenever App Sandbox is active OR macOS disables direct unentitled system-wide media-remote queries (macOS 15.4 and later, or helper adapter unavailable). Aggregates sandbox-compliant per-app controllers (`Apple Music`, `Spotify`, `YouTube Music`, `VLC`, and opt-in `Web Browsers`).
   - **System Now Playing (`nowPlaying`)**: Eligible only when unsandboxed (or when an explicitly enabled legacy direct-framework probe succeeds on macOS `< 15.4`), or when verified unsandboxed helper resources load cleanly without errors.
   - **Dedicated Sources (`appleMusic`, `spotify`, `youtubeMusic`, `vlc`, `browser`)**: Direct single-source monitoring.
3. **Failure Handling (Fail-Safe, Zero Crashes)**:
   - Never invoke `assertionFailure`, `fatalError`, or unguarded subprocess spawns when helper scripts/frameworks are absent or disallowed by App Sandbox.
   - If the system-wide adapter check fails or is ineligible under App Sandbox, classify legacy system-wide `Now Playing` as unavailable/deprecated (`isNowPlayingDeprecated = true`) and automatically route `.nowPlaying` / default selection to `.auto`.

## 3. Multi-Player Active Source Selection (`Auto` Mode)
1. **Candidate Sources**:
   - Each registered media source emits playback snapshots `(sourceId, isPlaying, title, artist, album, elapsedTime, duration, playbackRate, lastUpdated)` plus optional artwork/volume/favorite capabilities.
   - Sources with empty titles (`title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`) are treated as **inactive**.
2. **Active Candidate Rule**:
   - A source is currently **playing** if `isPlaying == true` and title is non-empty.
   - A paused source with a non-empty title remains **eligible (lingering)** for up to **600 seconds (10 minutes)** after the reference clock timestamp when it was last active, unless a playing source takes priority.
   - Once paused duration exceeds 600 seconds, the candidate expires and drops out of active selection.
3. **Priority & Tie-Breaking**:
   - Currently playing sources always outrank paused lingering sources.
   - Among multiple playing sources, pick the source with the most recent start/update timestamp (`mostRecentPlayDate`).
   - Among paused lingering sources (when nothing is playing), pick the source with the most recent active timestamp.
   - If two candidates share identical priority timestamps, break ties deterministically using a fixed priority order (`Apple Music` -> `Spotify` -> `YouTube Music` -> `VLC` -> `Web Browsers`, then lexicographical identifier).
4. **No Active Sources**:
   - When no playing or lingering source exists, emit an idle `PlaybackState` (`isPlaying = false`, empty strings for title/artist/album, `duration = 0`, `currentTime = 0`, `artwork = nil`).

## 4. VLC Integration Behavior
1. **Lifecycle**:
   - Observe workspace app launch/termination notifications for bundle identifier `org.videolan.vlc` alongside periodic lightweight polling while running (or immediate polling on launch).
   - When VLC is not running, emit an inactive/idle state without sending Apple Events (prevents macOS from auto-launching VLC).
2. **Metadata & Transport**:
   - Via temporary-exception Apple Events entitlement (`org.videolan.vlc`), read current item name, playing state, elapsed time, and item duration when running.
   - Support play/pause toggle, next item, previous item, and seek-to-second commands.
   - If title contains common media container extensions or URL prefixes and no separate artist is provided, present clean normalized display text.

## 5. Opt-In Web Browser Media Integration
1. **Default Disabled Policy**:
   - Web browser inspection is **disabled by default** (`enableBrowserMediaDetection = false`) because Apple Events JavaScript inspection requires per-browser user consent (*"Allow JavaScript from Apple Events"* in browser developer/view settings) as well as Automation authorization.
   - Enabling opt-in applies both when using `.auto` aggregation and when selecting the dedicated `.browser` source.
2. **Supported Running Browsers**:
   - Inspect only currently running browser bundle IDs (`com.apple.Safari`, `com.google.Chrome`, `com.brave.Browser`, `com.microsoft.edgemac`) in priority order. Never launch closed browsers.
3. **Inspection Behavior**:
   - Prefer active window/tab playback status from `navigator.mediaSession` or HTML5 `<video>` / `<audio>` elements (`paused == false` takes priority over paused tabs).
   - If browser JavaScript automation is not permitted by the user or returns an error, degrade silently to inactive without displaying modal errors during background polls, while surfacing clear setup guidance in Media settings.
   - Support play/pause and relative seek (`currentTime`) where permitted.

## 6. Playback Position Interpolation & Formatting
1. **Live Elapsed Estimation**:
   - Given snapshot `elapsedTime`, `playbackRate`, `isPlaying`, `duration`, and snapshot timestamp `lastUpdated`, compute current position at `now`:
     - If `isPlaying == false`, return clamped `elapsedTime` in `[0, duration]` (or `max(0, elapsedTime)` when `duration <= 0`).
     - If `isPlaying == true`, advance by `(now - lastUpdated) * max(0, playbackRate)` and clamp to `[0, duration]` when `duration > 0`.
2. **Idle Metadata Sanitization**:
   - Empty or whitespace-only titles produce inactive playback state. Placeholder filler strings (`"I'm Handsome"`, `"Me"`, `"Self Love"`, `"Not Playing"`, `"Unknown"`) are normalized to empty strings when inactive so views cleanly switch to idle typography (`"No Media"`).

## 7. Verification Criteria
- Standalone Foundation test suite verifies:
  1. Sandbox & OS version eligibility matrix (sandboxed vs unsandboxed `< 15.4` vs `>= 15.4`, helper available vs unavailable).
  2. Multi-source selector prioritization: playing overrides paused, newer play start overrides older playing source, paused source lingers < 600s and expires >= 600s, deterministic tie-breaking, and idle reset.
  3. Opt-in browser exclusion when disabled vs inclusion when enabled.
  4. Elapsed-time interpolation clamping and placeholder-string sanitization.
- App build syntax check (`swiftc -parse`), `plutil -lint` on project and entitlements, zero banned reference strings in added/modified code, and zero regressions in Step 1 (`NotchFoundationTests`) and Step 2 (`TelemetryTests`).
