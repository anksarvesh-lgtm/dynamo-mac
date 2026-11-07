# Changelog

## 1.3.2 · 2026-10-31

### Fixed
- A stream from the system feed (the TV app, QuickTime Player…) dropped out of the island a few
  minutes in, as soon as anything about playback changed. The feed process wedged on its first
  MediaRemote notification: the notification arrived on the queue the feed worked on, and
  Foundation waited there for the observer to finish, so nothing ran again and the island lost the
  stream ten seconds later. Notifications, work and replies now have queues of their own, and a
  watchdog in the feed plus one in the app replace a feed that goes quiet before the island notices.

### Changed
- The feed reports every app that publishes an item, not only the one macOS has elected as "now
  playing". With a browser tab paused in the background and the TV app playing, the island keeps
  the TV app; each app is its own source chip.
- Transport for a feed stream reaches the elected app through MediaRemote as before. For any other
  app the command would land on the elected one (macOS routes it there whatever app is named), so
  it is refused instead, and the TV app and QuickTime Player are driven by AppleScript, which asks
  for Automation permission once.

## 1.3.1 · 2026-10-31

### Fixed
- A stream from the system feed (the TV app, QuickTime Player…) vanished from the island about ten
  seconds after it was first seen unless playback changed. The adapter's two-second heartbeat never
  ran: its timer was released as soon as the function that created it returned. The island now
  keeps such a stream for as long as it plays.
- The feed process (Apple's perl running the adapter) could outlive NotchIsland when the app was
  ended without warning, which is how an in-app update relaunches it, and pile up one copy per
  relaunch. It now quits on its own within two seconds of losing its parent, and as soon as a write
  to the app fails.

## 1.3.0 · 2026-10-31

### Added
- Now Playing from any app. The TV app, Podcasts, QuickTime Player, IINA, a browser whose
  JavaScript switch is off, Music without an Automation grant: anything that publishes to Control
  Center now shows in the island with artwork, progress, play/pause, next/previous and seek, and
  joins the source chips next to the scripted streams. macOS stopped handing that feed
  (MediaRemote) to third-party apps in 15.4, so NotchIsland reads it the way the system still
  allows: through Apple's own `/usr/bin/perl`, which loads a small adapter library shipped in the
  bundle (`Sources/MediaRemoteAdapter`, built by SwiftPM as a dylib) and streams one JSON line per
  change. The scripted sources (Music, Spotify, VLC, browser tabs) keep their richer control and
  per-tab chips; the feed fills in everything else and stands in when a scripted app cannot be
  reached. No permission is needed for it.

### Changed
- Settings ▸ Modules names the feed; the browser note says a browser without the JavaScript switch
  still shows as one stream.

## 1.2.0 · 2026-10-31

### Added
- Updates from inside the app. Settings ▸ Updates asks GitHub Releases for the latest version
  (once a day while *Check for updates* is on, or with **Check Now**), shows what's new, and
  **Update Now** downloads the DMG, checks that the app inside is signed with the same certificate
  as the running copy, swaps it into place and relaunches. Every permission grant carries over, and
  Gatekeeper's "could not verify" dialog does not appear because nothing goes through a browser. A
  new version is announced once in the island (tap the HUD for the notes), as a line in the hover
  readout, as an **Update** button in the shade and as **Update to x.y.z…** in the menu bar;
  **Skip** silences one version. A copy that cannot be replaced (folder not writable) gets the DMG
  opened in Finder instead; a source or ad-hoc build only links to the release page.
- Settings ▸ General ▸ Theme: *Shadow under the open island* switch.

### Changed
- The island's shadow is a window's now: soft and mostly below the surface, instead of the dark
  halo that bled some 25 px into the menu bar on either side of the open island. The notch and its
  ears cast none.
- The update check is the app's only network request and sends nothing about you or your Mac;
  README and website say so instead of "no network".

## 1.1.1 · 2026-10-30

### Fixed
- Permissions that System Settings showed as allowed did not apply, and every restart or update
  looked as if it had lost them. macOS ties each grant to the signature of the build that asked for
  it. A grant made to 1.0.0 (signed ad hoc, so a different app to macOS after every build) or to a
  `swift run` binary never matches the signed releases, yet System Settings keeps listing it
  switched on, and flipping the switch does not refresh the stored requirement. NotchIsland now
  repairs this itself: on the first launch of a build with a different signature it removes its
  stale entries (`tccutil reset`) and asks for Accessibility again. Settings ▸ Permissions marks a
  grant that was there before and no longer applies, offers **Allow…** and **Reset…** per row,
  explains the leftover development entries (the ones with a terminal icon), and has **Reset All
  Permissions…** for Automation, Bluetooth and Camera.
- Accessibility granted while the app was running was not used until a relaunch: the hotkey kept
  its observe-only fallback. The CGEvent tap is now re-armed within three seconds of a change (and
  dropped again if the grant goes away).
- The app never asked for Accessibility, it only checked. **Allow…** in Settings and the first
  launch after an update now show the system dialog.

### Changed
- `scripts/make-dmg.sh` refuses to sign a release with a certificate other than the one recorded in
  `Resources/release-identity.sha1` (the hash macOS stores with every grant) unless `NEW_IDENTITY=1`,
  and refuses an ad-hoc build unless `ALLOW_ADHOC=1`. `scripts/signing-identity.sh --fingerprint`
  prints the current certificate. Either slip would make every user grant everything again.
- Settings ▸ Permissions ▸ About names the signing certificate and what it means for grants.

## 1.1.0 · 2026-10-29

### Fixed
- The island stuck on one browser while another one played. The browser status script stopped at
  the first tab with any media element, even a paused preview (YouTube's home page keeps one), so
  a tab playing further along the tab strip was never seen and the island stayed on whatever it
  had shown before. Every tab is now read and every stream is reported.

### Added
- Multiple sources. Every player and every browser tab with media is a stream. The island follows
  the one that started playing most recently (audible before muted), stays on the current one
  while nothing plays, and lists the others as chips in the media card. Tap a chip to switch; the
  choice holds until a new stream starts. Clicking the artwork of a browser stream jumps to its tab.
- Safari, and every Chromium browser next to Chrome, Brave and Edge: Arc, Vivaldi, Opera, Opera GX,
  Chromium and the beta/dev/canary channels. Safari needs Develop ▸ Developer Settings ▸ Allow
  JavaScript from Apple Events (turn on *Show features for web developers* in Settings ▸ Advanced
  first). Firefox has no scripting bridge.
- `NOTCHISLAND_MEDIA_LOG=1` logs every poll's streams and the chosen one.

### Changed
- Media that never played (hover previews, blocked autoplay) and muted looping decorations
  (landing-page hero videos) are ignored. Each tab gets at most 3 s, so a hung page can no longer
  freeze the island for a minute. A stream that one poll missed is held for a couple of seconds
  before the island moves on, so a tab closing elsewhere does not flip the card back and forth.

## 1.0.1 · 2026-10-29

### Fixed
- Notifications showed "Notifications unavailable: authorization denied" when NotchIsland had no
  Full Disk Access, while Settings ▸ Permissions still showed a green check. The readable-file test
  used `access(2)`, which macOS does not gate on Full Disk Access, so the real `open()` failed later
  with SQLite's `SQLITE_AUTH`. The app now opens the store for real, shows a clear hint in the
  island (click it to jump to the Full Disk Access pane), and Settings ▸ Permissions explains the
  steps and offers a Relaunch button. The store is re-checked every 10 s, so a grant is picked up.

### Changed
- Releases are signed with a stable, self-signed "NotchIsland Developer" identity instead of
  ad-hoc. macOS ties Full Disk Access and Accessibility grants to the app's signature, and ad-hoc
  signatures change on every build, which silently voided the grants. After installing 1.0.1 grant
  them once more; later updates keep them. New script: `scripts/signing-identity.sh`.

### Added
- The DMG carries a *Read me first.txt* with the exact steps for Gatekeeper's "could not verify"
  dialog on macOS 13/14 and 15+, plus the Terminal one-liner. README and website say the same.
- `scripts/make-dmg.sh` has a Developer ID path: with a "Developer ID Application" certificate and
  `NOTARY_PROFILE=<notarytool profile>` it signs with the hardened runtime
  (`Resources/NotchIsland.entitlements`), notarizes and staples the app and the DMG, which is the
  only way to make that dialog go away. Untested until a paid Developer ID is available.
- `NOTCHISLAND_PREVIEW=settings` (with `NOTCHISLAND_SETTINGS_TAB=…`) opens the Settings window.

## 1.0.0 · 2026-10-29

- First release.
