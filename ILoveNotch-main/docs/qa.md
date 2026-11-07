# QA

The [QA matrix](plan/implementation-plan.md#9-qa-matrix) as a checklist for each release. Checked
items are covered by automated tests or were verified on hardware for the current release
candidate; the rest are manual passes still to run before a public release.

## Automated (every pull request)

- [x] Reducer: every transition, suspension from sleep, display sleep, and lock, and 50,000
  random events against its invariants (`NotchReducerTests`)
- [x] Engine: timers, pointer reality checks, and 1,000 hover cycles without growth
  (`NotchEngineTests`, `NotchEnginePerformanceTests`)
- [x] Geometry: every state fits the panel on notched and notchless displays; the closed notch
  hides inside the camera housing; a pointer at the top edge counts (`NotchMetricsTests`)
- [x] Feature lifecycle: every feature starts, suspends, resumes, and releases everything,
  including the media helper, the audio tap, and the camera (`FeatureLifecycleTests`)
- [x] Media parsing, the fallback without the helper, the spectrum analyzer, system activities,
  shelf persistence, EventKit mapping, notes, shortcuts, and timers
- [x] Snapshots of every state and tab render
- [x] Quick Share: protobuf encoding against protobuf's own examples, frames and records round-trip,
  the UKEY2 key schedule and 4-digit code against an independent implementation, tampered, replayed,
  and off-curve messages refused, hostile file names, and this Mac sending to itself over loopback
  (1 file, 101 files, 200 MB byte-for-byte with one chunk in flight at a time, declines, cancels from
  either side, a stalled handshake, split and oversized frames) (`NotchTransferTests`)

## Performance

Run `scripts/soak.sh` (default 10 minutes; `scripts/soak.sh 480` for the 8-hour soak) against
the installed app. Gates are in the [plan](plan/implementation-plan.md#8-performance-gates).

| Run | CPU median / p95 | Memory (footprint) | Drift |
|-----|------------------|--------------------|-------|
| 2026-09-24, idle, 1 min, 14" MacBook Pro (Mac17,9), macOS 26 | 0.0% / 0.0% | 42 MB | 0 MB |
| 2026-09-24, 30 min, same Mac, mostly idle | 0.0% / 0.2% | 41–51 MB at rest; 130 MB peak for about a minute while the notch was in use | +3 MB |
| 8-hour idle | to run | | |
| 8-hour active | to run | | |

Clipboard history's poll, which runs only while the user has it on, was measured on its own on
2026-09-26 (same Mac): 60 checks in 30 seconds cost 13 ms of CPU including process start, about
0.04% of one core, and 2 wakeups a second. Off, it costs nothing.

The media helper, a separate process, used about 7 MB. In the 30-minute run the notch was used
once (60% CPU in that sample): memory rose to 130 MB and was back to 41 MB within a minute, so
it's released, not leaked. The 120 MB gate is for the resting notch; a gate for the open notch is
still to be set.

## Hardware checks

- [x] Notch geometry and top-edge hover on a 14" MacBook Pro
- [x] Clicks beside the notch reach the menu bar and apps underneath
- [x] Volume activity from a real volume change, with the meter
- [ ] Sleep and wake, display sleep, and screen lock: the notch hides and comes back
- [ ] Plugging in and removing an external display; changing resolution and scaling
- [ ] Clamshell mode with an external display
- [ ] Full-screen apps: no notch over them
- [ ] Notchless external display: the drawn notch sits inside the menu bar at every scaling, and the pill when picked
- [ ] Charger in and out: the battery activity
- [ ] Camera mirror: allow, deny, and revoke while running; the camera light turns off when the tab closes
- [ ] Waveform: allow and deny system audio capture; switching output devices while playing
- [ ] Sound tab: Spotify, a Chrome tab, and a Safari tab each turn down by ear with no echo or click; mute and
  unmute while playing; 100% hands the app back; switch to AirPods (and back) from the list mid-song; a Bluetooth
  speaker appears when it connects; the microphone fader moves the input level and mutes it in a call; relaunch keeps
  the levels; with system audio recording denied, apps stay at their own volume and the tab says why
- [ ] Network: a large download shows its speed on the closed notch within a few seconds and "Downloaded …" when it
  ends, while a web page or a video doesn't; the speed stays under a meeting countdown and Keep Awake; NetSpeed's
  history appears the first time; the numbers match Activity Monitor's Network tab; Wi-Fi off and on, an iPhone
  hotspot, and a VPN don't make a spike; lock the Mac through a download and the hours it ran fill in
- [ ] Replace the volume display: grant and revoke Accessibility while running
- [ ] Media: Apple Music, Spotify, a browser, and QuickTime; kill the helper (`pkill -f mediaremote-adapter`) and check Media falls back
- [ ] Shelf: deleted, moved, and corrupt files
- [ ] Permissions granted, denied, and revoked while running (Calendar, Reminders)
- [ ] Tasks: quick add in plain words, a timed task's alert on the notch and on iPhone, Snooze, and Block Time
- [ ] Calendar: edit an event's title and time from the notch and delete one (a second click confirms), then
  check both in Calendar and on iPhone; a repeating event changes only that day, and an invitation offers neither
- [ ] Notes in an iCloud Drive folder: edits reach the iPhone's Files app, and a file named there keeps its name
- [ ] Control-Option-N starts a note from another app and hands the keyboard back when the notch closes
- [ ] Light and dark mode, Increase Contrast, Reduce Motion, Reduce Transparency, VoiceOver, keyboard-only use
- [ ] Glass theme (macOS 26): every tab's text readable over a white, a black, and a busy wallpaper, and the glass
  the same on every tab, before and after typing in one; clicks on empty glass and between a tab's icon strokes
  stay in the notch; the closed notch stays black, and so does the housing on a drawn notch; Reduce Transparency
  and Increase Contrast switch it to black while it's open

### Android (Quick Share), with a real phone on the same Wi-Fi

Stream `log stream --level debug --predicate 'subsystem == "cafe.opennotch.app" && category == "transfer"'`
while testing, and keep the log of anything that fails.

- [ ] Phone to Mac, 1 photo: the codes match, it arrives, and it's on the shelf
- [ ] Phone to Mac, a 1–2 GB video: speed limited by the Wi-Fi, the Mac's memory stays flat
- [ ] Phone to Mac, 100 photos: all arrive, one progress bar
- [ ] Phone to Mac, a link and some text: both on the clipboard, Open for the link
- [ ] Mac to phone, 1 file and many files, from the list and from the QR code
- [ ] Decline on each side: a clear message, no leftover files
- [ ] Cancel partway on each side: partial files deleted
- [ ] The phone set to Contacts or Your devices: the QR code still works
- [ ] 2.4 GHz and 5 GHz Wi-Fi: note the speeds
- [ ] Mac asleep, lid closed, locked: nothing announced, and visible again after waking
- [ ] Local Network access denied: the shelf and Settings say so and open the right pane

## Operating systems

- [ ] macOS 14.6
- [ ] macOS 15.6
- [x] macOS 26 (development)
- [ ] macOS 27
- [ ] macOS 27: a "When I receive a notification" automation can pass the notification to Show in Notch
