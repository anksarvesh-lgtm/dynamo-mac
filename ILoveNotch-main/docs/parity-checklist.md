# Parity checklist

User-visible behaviors ILoveNotch should cover, grouped by target release. This
list describes behavior only. How any other app implements these features is
out of scope and must not be copied.

A box is checked once the behavior ships in a build you can run from `main`.
Each group names the [implementation plan](plan/implementation-plan.md) phase
that delivers it.

## v0.1: notch shell (Phases 1–2)

- [x] Opens on hover after a short dwell, or immediately on click or a two-finger pull down
- [x] Closes shortly after the pointer leaves; brief overshoots don't close it
- [x] Pin keeps it open; click-away closes it, and so does Escape while typing
- [x] Remembers the last open tab
- [x] Clicks beside the notch still reach the menu bar and the apps underneath
- [x] Stays out of full-screen apps and stops during sleep, display sleep, and screen lock
- [x] Works on notchless displays (floating pill) and, optionally, on every display
- [x] Menu-bar item for Settings, Sponsor, and Quit, reachable even if the notch misbehaves
- [x] Settings: launch at login, displays, turn features on or off, and reset
- [x] Respects Reduce Motion and Increase Contrast; VoiceOver labels and Open/Close actions
- [x] Dragging files over the notch opens it to the shelf
- [x] Closed, the notch hides behind the camera housing; hovering grows it slightly
- [x] A live activity's symbol and text stay together: in a row just under the camera, or, while ongoing, in a tab beside it over the menu bar
- [x] Switching tabs slides the content across, and the selection moves with a jelly stretch
- [x] Resize the open notch by dragging its bottom-right corner, between a smallest and a largest size
- [x] The tab row holds the tabs, the pin, and Settings; more tabs make the tabs narrower, never crowded
- [x] No scroll bars over the notch's content; long lists and pages fade at their edges instead
- [x] Tabs adapt to shorter notches: media drops its waveform, then shrinks its artwork; laps move beside the stopwatch
- [x] Pushing the pointer against the top edge over the notch opens it
- [x] Choose how the notch opens and closes (spring, jelly, pop, smooth, snappy, or instant), with a preview
- [x] Builds from a checkout update themselves from the menu bar (**Update ILoveNotch**)

## v0.2: media and shelf (Phase 3)

- [x] Shows now-playing title, artist, artwork, and progress, from any app
- [x] Play/pause, next, and previous controls; clicking the artwork opens the player
- [x] Wavy seek bar you can drag to seek
- [x] Waveform that follows the music's loudness across frequencies (with system audio permission)
- [x] Brief live activity when the track changes
- [x] Drop files onto the notch to hold them on a shelf
- [x] Drag shelf files back out, preview with Quick Look, and send with AirDrop
- [x] Shelf survives relaunch and follows renamed files; missing files are shown, not silently dropped
- [x] Clear message when a feature is unavailable (for example, Media's fallback) or has nothing to show

## v0.3: productivity (Phase 4)

- [x] Today's calendar events, with a clear path when calendar access is off
- [x] Reminders-backed tasks: check off, add, pick a list; they sync to iPhone through iCloud
- [x] Recently completed tasks in a collapsible section; tap one to reopen it
- [x] Quick local notes that save as you type
- [x] Shortcut launcher that runs shortcuts in the background
- [x] Timer and stopwatch with rolling-digit animation and a "Timer done" live activity
- [x] Every stopwatch lap, newest first, in a scrolling list
- [x] Per-feature settings, including access status for Calendar and Reminders

## Tasks, Calendar, and Notes revamp

- [x] Tasks grouped by due date (Overdue, Today, Tomorrow, Next 7 Days, Later, No Date) or by list
- [x] Quick add that reads dates, times, "!"-style priorities, "#list", and repeats as you type
- [x] Hover actions on a task: due date, priority, list, rename, delete, and block time in Calendar
- [x] Alerts at the due time through Reminders, and a due task shown on the notch with Done and Snooze
- [x] Calendar lists tasks due today and adds events typed in plain words
- [x] Your own events edited in place (title and time) or deleted, from hover buttons, a double-click, or the context menu; invitations are left to Calendar
- [x] Notes with hover highlights, a sliding selection, colors, pins, search, and sort
- [x] A note's unticked checklist items ("- [ ]") sent to Tasks in one click
- [x] Notes in a folder of your choice (such as iCloud Drive) to reach them on iPhone, where files you named keep their names; share to Apple Notes
- [x] Control-Option-N opens a new note from any app

## v0.3+: camera and system (Phase 5)

- [x] Front-camera mirror, off until turned on; the camera runs only while the Mirror tab is open
- [x] Volume change indicator with a meter, following the output device
- [x] Charging and battery activity: charger in or out, 20% and 10% left, and full
- [x] Replace the macOS volume display (opt-in, needs Accessibility access)
- [x] Bluetooth accessory battery when it connects (experimental: Apple keyboards, mice, and trackpads)
- [x] Each system activity can be turned off in Settings › Live Activities

## v0.5: AI usage (Phase 8)

- [x] Usage tab: session and weekly limits, credits, spend, and reset countdowns per AI coding subscription
- [x] Providers: Antigravity, Claude, Codex, Copilot, Cursor, Devin, Grok, Ollama, OpenCode, OpenRouter, Z.ai
- [x] Each provider off until turned on; no refresh while hidden unless a background interval is chosen
- [x] Pace for each limit: plenty left, cutting it close, or when it runs out
- [x] Spend for today, yesterday, and the last 30 days, and the daily usage trend
- [x] Live activity when a limit is close or resets
- [x] A card per provider that's on, and back from a provider's detail to the cards
- [x] Cards share the width: one spans it, two split it, and a last short row sits centered
- [x] Cards fit the notch at any size: the grid picks the columns, and each card shows what its size holds (the ring, then fewer limits) instead of being cut off
- [x] A tray under the cards offers every other provider; the ones signed in on this Mac are in color
- [x] API keys for OpenRouter and Z.ai, pasted in Settings › AI Usage and kept in the keychain
- [x] Provider logos from theSVG

## v1.1: the roadmap's picks

- [x] Join meeting: a Join button on events with a Zoom, Google Meet, Teams, Webex, Whereby, Jitsi, or FaceTime link in their URL, location, or notes; right-click copies the link
- [x] A countdown in the closed notch for the five minutes before a meeting with a link, opening with its name; hovering it opens the Calendar tab
- [x] A keyboard shortcut from any app (⌃⌥O, recorded in Settings › General) opens the notch on the display under the pointer; it, Escape, or a click away closes it
- [x] Keep Awake in the Timer tab: the Mac and its display stay awake for 30 minutes to 4 hours or until turned off, shown in the closed notch with the time left; it ends when the Mac sleeps anyway, on quit, or when the Timer tab is turned off
- [x] Show in Notch: a Shortcuts action and an `ilovenotch://show` link put a message and a symbol in the notch for 1 to 30 seconds, in both editions, without taking focus
- [x] Agent status: an Agents tab lists Claude Code and Codex sessions, working, waiting for approval, or finished, with a button back to each one's terminal
- [x] While an agent waits for approval the closed notch shows it until it's answered, and a session that finishes while its app is in the background is announced
- [x] Connecting a tool adds hooks to its own settings next to any others, and disconnecting removes exactly those; GitHub build only
- [x] Clipboard history, off until turned on: text, links, images, and files, newest first, searchable, with favorites that stay; click (or Return) copies one again
- [x] ⌃⌥V opens the Clipboard tab from any app with the search field ready
- [x] Skips what the copying app marks secret or temporary and copies from password managers; guides the user to "Paste from Other Apps" when macOS would ask each time
- [x] Notch on every display: a display without a notch gets one drawn inside its menu bar, as tall as the bar and as wide as the Mac's own notch (or a MacBook's); Settings › Displays picks Notch or Pill per display
- [x] Glass look: Settings › Appearance › Theme opens the notch in glass on macOS 26, a live blur of what's behind it with Liquid Glass edges, the same on every tab whether or not the notch has the keyboard, and clickable everywhere; closed it stays black in the camera housing, and Reduce Transparency, Increase Contrast, and macOS 14 and 15 keep it black

## Tabs in your order

- [x] A grid button after the tabs opens the app drawer: every app as a grid, like Launchpad, the open one lit and those turned off dimmed; a click opens one (turning it on if it was off) and the grid button goes back to the drawer; a small notch gets smaller tiles, so every app fits
- [x] An app opened from the drawer shows at the end of the tab row while it's open
- [x] The drawer's Edit tile (or a right-click on the tabs) edits the tab row inside the notch: the tabs wiggle and drag into a new order, and a tray below holds the apps kept in the drawer
- [x] Drag a tab down into the tray, or click its minus, to keep it in the drawer, still on; click or drag one back into the row, where a gap opens for it; a drawer tile's right-click does the same; the row keeps at least one tab
- [x] Every change applies at once and persists; an app in the drawer keeps its place, a feature added by an update joins the end, and Settings' sidebar lists the tabs in the same order
- [x] The notch stays open while editing; Done goes back to the drawer, and closing the notch ends both
- [x] VoiceOver: Move Left, Move Right, and Keep in the Drawer on each tab, and a tray app's own action adds it

## Sound tab

- [x] A Sound tab of its own, beside Media: the Mac's outputs, or with a switch its inputs (speakers, wired headphones, AirPods and other Bluetooth devices while connected, AirPlay, displays), each with its icon; a click makes one the Mac's output or input
- [x] Faders for the output's volume (with its AirPods or headphones when that's what plays) and the microphone's, in orange; a click on the icon mutes either
- [x] A fader per app playing sound, tinted from its icon, in the order they started; drag to set its volume and click its icon to mute; each app keeps its volume until it's back at 100% or reset (Settings › Sound › Reset All)
- [x] Helpers count as their app: Chrome's, Spotify's, and the WebKit process behind Safari (or any app that plays web audio)
- [x] Hovering the volume keys' level in the closed notch opens the Sound tab
- [x] Nothing listens while the tab is closed and every app is at 100%; an app turned down plays through a tap only while it plays, and a muted one is silenced at its source with no audio work at all
- [x] Without the system audio recording permission apps keep their own volume, and the tab links to Privacy Settings
- [x] GitHub build only (the App Store edition keeps the waveform)
- [ ] Checked by ear on a MacBook: each of the [hardware checks](qa.md#hardware-checks)

## Network tab (NetSpeed, absorbed)

- [x] The download speed as it happens, the upload's under it, over a graph of the last minute (NetSpeed's menu bar item and sparkline)
- [x] Downloaded and uploaded over the last 24 hours, 7 days, 30 days, or 12 months, as bars by the hour, day, or month, with the range's totals; pointing at a bar shows its time and numbers (NetSpeed's dashboard)
- [x] The closed notch shows the speed while a transfer runs (1 MB/s for 4 s, until under 250 KB/s for 5 s), and "Downloaded 1.2 GB" when one of 50 MB or more ends; always or never in Settings; hovering it opens the tab; it stays under other live activities
- [x] Physical interfaces only (Wi-Fi, Ethernet, iPhone tethering), each counted on its own, so one that restarts or appears never counts as a spike
- [x] One row per local hour in SQLite; what moves while locked or asleep is shared among those hours; NetSpeed's minute rows come in by the hour, once, into an empty history
- [x] Readings every second only while a speed shows, every 3 s while the closed notch waits for a transfer, else hourly; stopped with the notch and when the tab is off
- [x] Both editions (the counters and SQLite work in the App Sandbox)
- [ ] Checked on a MacBook: each of the [hardware checks](qa.md#hardware-checks)

## Android sharing ([plan](filesharing.md))

- [x] Phone to Mac with Quick Share: the notch opens on the shelf with the phone, what it's sending, and the code both screens show; nothing is saved until Accept
- [x] Received files stream to Downloads (or a chosen folder) in 512 KB chunks, take a clean, numbered name only once whole, join the shelf, and are marked as downloaded
- [x] Text and links go to the clipboard, and web links get Open
- [x] Mac to phone from the shelf: a send window lists phones nearby while it's open, with the code, the phone's answer, and progress
- [x] A QR code in the send window, for phones that won't appear otherwise (Samsung's among them); the files go straight to the phone that scans it
- [x] Cancel from either side, a decline, or a phone that doesn't answer in 60 seconds ends cleanly, with no partial files left
- [x] Visible only when chosen: 10 minutes from the shelf, while the notch is open (and a minute after), or always; never while asleep or locked
- [x] A clear message and a fix when macOS denies local network access
- [ ] Verified with a real phone (S25 Ultra): each of the [manual checks](qa.md#hardware-checks)
- [ ] The App Store edition (after the GitHub build ships it)

## Media revamp

- [x] Shuffle and repeat (off, all, one) beside the controls, lit in the cover's color; from MediaRemote, or Music's and Spotify's AppleScript where it's missing (Spotify)
- [x] 15-second skips in place of next and previous for players that skip by time (podcasts, audiobooks)
- [x] Music's up next, from the playlist it plays from; click a track to play it
- [x] Spotify's recently played, to play again (its queue isn't readable: no AppleScript, and the Web API is capped at 5 users in development mode since February 2026)
- [x] Music's own lyrics, when saved with the track (no outside lyrics service)
- [x] The cover and title in the closed notch while playing and for a minute after a pause, under timers and meetings
- [x] Output and volume panel from the Sound tab's devices and faders (GitHub build, Sound tab on)
- [x] Two-finger swipe across the player skips tracks
- [x] App Store edition: controls for Music and Spotify through scripting access groups, and Music's cover
- [ ] Automation prompt, shuffle, repeat, up next, and recently played checked by hand with Music and Spotify
- [ ] Closed-notch tab measured for CPU while a song plays ([efficiency](../README.md#efficiency))
- [ ] App Store edition's controls accepted by App Review

## Settings like System Settings

- [x] A sidebar of pages, each marked by a white symbol on a colored tile: the app at the top (opening About), General, Appearance, Displays, and Live Activities, then a page per tab in the notch's order, with "Off" beside the tabs that are off
- [x] Each page opens with its icon, its name, and a line on what it's for; a tab's page has the tab's switch there, then its settings while it's on
- [x] The theme is picked from small previews of the open notch; Reset to Defaults asks first
- [x] The menu bar item names the version and has Settings, updates, About, What's New, Sponsor, and Quit, each with a symbol

## Later

- [ ] Brightness display (blocked: Apple silicon has no public API to read or set brightness)
- [ ] AirPods and other Bluetooth batteries (blocked: no public API)
- [ ] General notification mirror (deferred: no clean public API)
- [x] Signed, notarized DMG on GitHub Releases with in-app updates ([1.0.0](updates.md#public-releases))
- [x] Sandboxed Mac App Store edition ([1.0.0 in review](plan/implementation-plan.md#app-store-edition))
