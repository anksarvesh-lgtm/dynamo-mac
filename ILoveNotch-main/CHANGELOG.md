# Changelog

Every notable change to ILoveNotch, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Each version's section is also its release notes: `make release` puts it on the
GitHub release and in the app's update prompt. Changes go under **Unreleased**
as they land, written for the people who use the app
([CONTRIBUTING.md](CONTRIBUTING.md#versioning-and-releases)).

## [Unreleased]

## [1.5.0] - 2026-11-04

ILoveNotch 1.5 comes from your feedback: edit the tab row right in All Apps, put your tasks in your own order, and paste with ⌘V.

### Added

- **Put your tasks in your own order.** Drag a task onto another in the same section to move it there; that section keeps your order, and new tasks join its end, as in Reminders. Sections you never rearrange stay soonest due first.

### Changed

- **Edit the tab row right in All Apps.** Edit no longer opens another screen: the tabs wiggle where they are, each with a minus to keep it in the drawer, the apps off the row get a plus, and Edit turns into Done.

### Fixed

- **⌘V pastes in the notch.** Paste, copy, cut, select all, undo, and redo now work in every text field, in the notch and in Settings.

## [1.4.0] - 2026-10-09

ILoveNotch 1.4 makes the Media tab a fuller player: shuffle and repeat, Music's up next, the cover in the closed notch, and controls that work in the App Store edition too.

### Added

- **Shuffle and repeat in the Media tab**, lit in the cover's color while on: repeat goes from off to all to this track. They work in Music, Spotify, and other players that report them, and podcasts and audiobooks get 15-second skips in place of next and previous.
- **Up next in Music, recently played in Spotify.** The list button shows what Music plays after this track; click one to play it. Spotify keeps its queue to itself, so its list holds the tracks you've played, to play again.
- **Music's lyrics**, when the track has lyrics saved with it.
- **What's playing in the closed notch.** The cover and title stay beside the camera while music plays, and for a minute after it pauses. Turn it off in Settings › Media.
- **Output and volume from the player.** Switch speakers, headphones, or AirPods, and set the Mac's volume and the player's own, without leaving the Media tab (GitHub build, with the Sound tab on).
- **Swipe to skip.** Two fingers sideways across the player go to the next track or the one before.
- **Media controls in the App Store edition.** Play, pause, skip, seek, shuffle, and repeat now work for Music and Spotify, and Music's cover shows.

macOS asks once before ILoveNotch controls Music or Spotify this way (Privacy & Security › Automation), the first time you press one of these buttons.

## [1.3.0] - 2026-10-02

ILoveNotch 1.3 puts the tabs on Liquid Glass with new icons, lets you select and clear clipboard items, and no longer quits as it opens when a reminder is due.

### Added

- **Select and clear in the Clipboard tab.** Select ticks items to delete together, favorites included, with Select All for what the search shows. Clear deletes everything but favorites, after asking once more.

### Changed

- **Tabs in Liquid Glass, with new icons.** The tab row, All Apps, and the pin with Settings sit on glass, the way macOS 26 draws a toolbar. The notch's icons are now from Tabler Icons, drawn on one grid with one stroke, so every tab looks the same size, and the Network tab is a UFO, beaming your data up and down.

### Fixed

- ILoveNotch no longer quits as it opens when a reminder with a time is due within a day.

## [1.2.0] - 2026-09-28

ILoveNotch 1.2 turns each app's volume up or down, shows your network speed, puts the tabs in your order, and lays Settings out like System Settings.

### Added

- **Sound tab.** Every app playing sound gets a fader of its own, with its icon, to turn it down or mute it, beside your output's and microphone's volume. Switch between your speakers, headphones, AirPods, AirPlay, and displays with a click. Hovering the volume in the closed notch opens the tab.
- **Network tab.** Your download and upload speed as it happens, over a graph of the last minute, and how much you've moved by the hour, day, or month. A big download shows its speed beside the notch, then how much it moved. If you used NetSpeed, its history comes along.
- **Tabs in your order.** Drag the tabs into your own order right in the notch, and keep the ones you use less in the app drawer.
- **App drawer.** The grid button after the tabs opens every tab as a grid, like Launchpad, the ones you've turned off included.
- **About and What's New** in the menu bar item.

### Changed

- **Settings, redesigned.** Laid out like System Settings: a sidebar with a page for each part of the app and each tab, marked with colored icons, and each tab's switch at the top of its page. Pick the theme from previews of the notch.
- The menu bar item's menu has symbols, like the system's own menus.
- Reset to Defaults asks before it resets.
- AI Usage reads large session logs with a fraction of the memory: an 80 MB log peaks at 6 MB, not 120 MB.

### Fixed

- On a display without a notch, the notch no longer sits on top of a full-screen app.

## [1.1.0] - 2026-09-27

ILoveNotch 1.1 shares with Android phones, opens in Liquid Glass, remembers what you copy, and puts a notch on every display.

### Added

- **Quick Share with Android.** Send shelf files to an Android phone, and accept files and links from one right in the notch, over your Wi-Fi. Receiving stays off until you turn it on.
- **Liquid Glass.** On macOS 26, the open notch can be glass instead of black: Settings › General › Theme.
- **A notch on every display.** Displays without a notch get one drawn inside the menu bar, or a floating pill.
- **Open it from any app.** Press ⌃⌥O; press it again or Escape to close.
- **Clipboard history.** Search what you've copied (text, links, images, and files) with ⌃⌥V, and keep favorites. It's off until you turn it on, and it skips passwords and anything marked private.
- **Agent status.** The notch tells you when Claude Code or Codex needs your approval or finishes, and the new Agents tab takes you back to its terminal.
- **Join calls.** A Join button for Zoom, Google Meet, Teams, Webex, and FaceTime, with a countdown in the closed notch for the five minutes before a call starts.
- **Keep Awake.** Keep your Mac from sleeping for a while, or until you turn it off, from the Timer tab.
- **Show in Notch.** Put your own message in the notch from a Shortcuts action or an `ilovenotch://show` link.
- **Tasks, Calendar, and Notes, rebuilt.** Add reminders and events in plain words ("Lunch tomorrow 1pm"), group tasks by date or list, see today's tasks next to your events, and edit or delete events in place. Notes are Markdown files named after their first line, and they can live anywhere, iCloud Drive included.

### Changed

- A timer, Keep Awake, or an upcoming call stays in the closed notch until it ends, with its icon and text side by side.
- The open notch can shrink to 414 × 200, and every tab still fits.
- Notes search tucks into its icon, and the color swatches unfold from the color dot.
- AI Usage cards fit any notch size.

### Fixed

- Renaming a task now takes your typing.
- A Quick Share transfer the other side cancels now says "Cancelled", not "Lost the connection".

## [1.0.0] - 2026-09-24

The first release of ILoveNotch: your MacBook's notch, finally useful.

### Added

- **The notch.** Opens when you hover it, click it, or pull down with two fingers, and closes when you move away. Pick how it opens and closes, resize it from its corner, and pin it open.
- **Media.** What's playing in any app, with artwork, controls, a seek bar, and a live waveform.
- **Shelf.** Drop files on the notch, then drag them out, preview them with Quick Look, or AirDrop them.
- **Calendar and Tasks.** Today's events, and your Reminders, synced with your iPhone.
- **Notes, Shortcuts, and Timer.** Quick notes, your shortcuts one click away, and a timer and a stopwatch with laps.
- **Mirror.** Your camera, only while its tab is open.
- **AI Usage.** How much of your Claude, Codex, Cursor, Copilot, and other AI plans you've used, with reset countdowns.
- **System activities.** Volume, charging and battery, and Bluetooth accessory batteries show briefly in the notch.
- Signed and notarized by Apple, with updates through Sparkle, and on Homebrew: `brew install --cask niyamvora/tap/ilovenotch`.

[Unreleased]: https://github.com/niyamvora/ILoveNotch/compare/v1.5.0...HEAD
[1.5.0]: https://github.com/niyamvora/ILoveNotch/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/niyamvora/ILoveNotch/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/niyamvora/ILoveNotch/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/niyamvora/ILoveNotch/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/niyamvora/ILoveNotch/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/niyamvora/ILoveNotch/releases/tag/v1.0.0
