# App Store listing

**Status: 1.4.0 (build 157) live** at US$1.99 (<https://apps.apple.com/app/id6815805975>);
**1.5.0 (build 163) in review** since 4 November 2026, released automatically once approved, and in
TestFlight's Public group awaiting Beta App Review. History: 1.0.0 was submitted on 24 September and
rejected on 29 September for the Sponsor link (guideline 3.1.1: no payments outside In-App
Purchase) and for "Allow Access" buttons before permission prompts (5.1.1(iv): say Continue); the
same version, renamed 1.3.0 (build 150) with both fixed, was resubmitted on 2 October and went live
on 7 October. 1.4.0 was first submitted with build 156, then pulled and resubmitted with 157 for
the Spotify Automation fix (f57875a). Change the listing here and in App Store Connect together.
Character limits are App Store Connect's.

## What's New in 1.5.0

Made from your feedback.

- Edit the tab row right in All Apps: the tabs wiggle where they are, tap − to keep one in the
  drawer or + to add one, and Edit turns into Done.
- Put your tasks in your own order: drag a task onto another in the same section to move it there.
  New tasks join the end, as in Reminders.
- ⌘V pastes in the notch, and copy, cut, select all, undo, and redo work in every text field.

The App Store edition is sandboxed: it has every tab except Sound, AI Usage, and Agents, and no
Quick Share. Media shows what's playing in Music and Spotify from their public notifications and,
since 1.4.0, controls them through their scripting access groups; Music's cover shows, while
Spotify's is a tinted stand-in (its artwork would be the edition's first network request). The
screenshots still show the full edition in places: the AI usage chip on the designed shots, and in
1.4.0's Media capture, a tab row with Sound, AI Usage, and Agents and Spotify's cover. If App Review
objects, replace those.

## Identity

| Field | Value | Limit |
|-------|-------|-------|
| Name | ILoveNotch | 30 |
| Subtitle | Your notch, finally useful | 30 |
| Bundle ID | `cafe.opennotch.app` (App Store app ID 6815805975), shared with the direct download so settings and permissions carry over | permanent |
| SKU | `ilovenotch-mac` | internal |
| Primary category | Productivity (matches `LSApplicationCategoryType`) | |
| Secondary category | Utilities | |
| Age rating | 4+ (every question answered None) | |
| Content rights | Doesn't use third-party content | |
| Price | US$1.99 (set for the United States; Apple prices the other storefronts from it), in all 175 countries and regions | |
| Copyright | 2026 Niyam Vora | |

## Promotional text (170)

Your MacBook's notch, put to work. Hover to see what's playing, drop files on a shelf, check off
tasks, and start a timer without leaving what you're doing.

## Description (4,000)

ILoveNotch turns the notch on your MacBook into a small, fast tray for the things you reach for all
day. Hover over the notch or click it, and it opens right where you're already looking.

MEDIA
See what's playing in Music and Spotify, with a waveform that moves with the sound. Play, pause,
skip, shuffle, and repeat from the notch, and pick what plays next in Music.

SHELF
Drop files on the notch to keep them close, then drag them out, preview them with Quick Look, or
send them with AirDrop.

CLIPBOARD
What you copy, kept and searchable with Control-Option-V, with favorites. Off until you turn it on.
Select items to delete together, or clear everything but your favorites.

CALENDAR AND TASKS
Today's events and the tasks due today at a glance, and your Reminders, synced to your iPhone. Add
a task in plain words, like "Pay rent Friday 9am", group tasks by date or list, block time for
one in Calendar, and see it on the notch when it's due.

NOTES, SHORTCUTS, AND TIMER
Markdown notes that save as you type, with colors, pins, search, and checklists you can send to
Tasks, in a folder of your choice such as iCloud Drive. Your shortcuts one click away, a timer,
and a stopwatch with laps.

NETWORK
Your download and upload speed as it happens, over a graph of the last minute, and how much you've
moved by the hour, day, or month.

MIRROR
A quick look at your camera before a call, only while its tab is open.

MADE FOR MAC
Native and light: no accounts, no tracking, and nothing running when you aren't using it. Choose
how it opens and closes, drag its corner to resize it, pin it open, and use it on every display. On
Macs without a notch it sits at the top of the screen as a small pill.

Open source.

(The App Store edition is paid, so its listing never says "free".)

## Keywords (100)

notch,menu bar,now playing,shelf,drag and drop,airdrop,reminders,calendar,timer,notes,stopwatch

## URLs

| Field | Value |
|-------|-------|
| Support URL | https://github.com/niyamvora/ILoveNotch/issues |
| Marketing URL | https://github.com/niyamvora/ILoveNotch |
| Privacy Policy URL | https://github.com/niyamvora/ILoveNotch/blob/main/PRIVACY.md |

## Screenshots

Mac screenshots are 16:10 (2880×1800, 2560×1600, 1440×900, or 1280×800), up to 10, without
transparency. 1.0.0 has nine, in this order: the designed hero, Shelf, Timer, Tasks, Notes,
Calendar, and Shortcuts shots at 1440×900, then two desktop captures (Media and AI Usage) cut to
2880×1800 above the Dock. 1.4.0 has eight: the same seven designed shots, then the 1.4 Media player
on the desktop (`08-media-1.4.png`, 2560×1600, cropped from a full-screen capture around the notch
to leave out the Dock and desktop icons); the old Media and AI Usage captures were dropped. The
files are kept outside the repository, with the launch assets.

## App preview

A Mac app preview is 1920×1080, 15 to 30 seconds, at most 30 fps and 500 MB, H.264 with a stereo
AAC track (256 kbps, 44.1 or 48 kHz). Use music you have the rights to, or none. 1.0.0's preview is
the demo recording from 0:07, Media through Timer, stopping before AI Usage:

```bash
ffmpeg -ss 7 -t 29.95 -i nook.mp4 -vf "scale=1920:1080:flags=lanczos,fps=30,format=yuv420p" \
  -c:v libx264 -profile:v high -level 4.0 -b:v 11M -maxrate 12M -bufsize 24M -x264-params nal-hrd=vbr \
  -preset slow -af "afade=t=in:d=0.3,afade=t=out:st=28.45:d=1.5" -c:a aac -b:a 256k -ar 48000 -ac 2 \
  -movflags +faststart app-preview.mp4
```

## Export compliance

`App/AppStore/Info.plist` sets `ITSAppUsesNonExemptEncryption` to `NO`: this edition makes no
network requests, so App Store Connect doesn't ask on each upload.

## App Privacy (answered in App Store Connect)

Data collection: **None** ("Data Not Collected"). ILoveNotch doesn't collect data or track.
Calendar, Reminders, camera, and system audio stay on the Mac and are never sent anywhere. Only the
website can answer this; the API can't.

## Review notes

ILoveNotch is a menu-bar-style utility with no Dock icon. To open it, move the pointer to the notch
(or the pill at the top of the screen on Macs without a notch), or click the ILoveNotch item in the
menu bar and choose Settings. Calendar and Reminders access is requested only when you click
Continue in those tabs. The Mirror tab is off until turned on in Settings › Mirror (or opened from
the app drawer, the grid button after the tabs), and uses the camera only while it's open. Media shows what's playing in Music or Spotify; its waveform asks for
system audio recording permission and analyzes the sound on the Mac without recording it. Its
playback, shuffle, and repeat buttons control Music and Spotify through the scripting access groups
they publish (`com.apple.security.scripting-targets`); macOS asks for Automation permission the
first time one is pressed. No account or sign-in is needed, and the app makes no network requests.

New in 1.5.0: open the notch, click the grid button after the tabs (All Apps), and click Edit: the
tabs wiggle in place; click − on a tab to keep it in the drawer, + on an app to add it to the row,
or drag them, then click Done. In the Tasks tab, drag a task onto another in the same section to
reorder it. Command-V now pastes in the notch's text fields, such as the new task field.

To try Media's controls (new in 1.4.0): play a song in Music or Spotify, open the notch on the
Media tab, and press play/pause, next, shuffle, or repeat. macOS asks once for Automation permission
for that app. The list button shows Music's up next; for Spotify, the tracks played since launch.

(1.3.0's notes opened with what changed since the rejection: the Sponsor link gone from this
edition, and Continue buttons before the camera, Calendar, and Reminders prompts.)

## TestFlight

External testers join the "Public" group at <https://testflight.apple.com/join/6p3zqhCS>. Its test
information (description, feedback email, and the same review contact and notes) is filled in, and
each build's What to Test says to try every tab and send feedback from TestFlight.
