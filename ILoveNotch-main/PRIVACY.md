# Privacy

ILoveNotch is local-first.

- No accounts, analytics, telemetry, or device fingerprinting.
- The network is used for three things only: the update check against GitHub
  Releases, the AI Usage providers you turn on (below), and sharing with
  Android phones when you use it, which stays on your local network (below).
  With no provider on, the AI Usage tab never touches the network.
- Everything ILoveNotch creates (settings, notes, shelf items) stays on your Mac,
  unless you choose a notes folder that syncs, such as one in iCloud Drive.
- System permissions (Calendar, Reminders, Camera, and so on) are requested only
  when you enable the feature that needs them. Denying one disables only that
  feature.
- The Mirror tab is off until you turn it on, and uses the camera only while
  that tab is open. Nothing is recorded or saved.
- Replacing the macOS volume display is off until you turn it on. It asks for
  Accessibility access to catch the volume keys; ILoveNotch takes only the three
  volume keys and passes every other event through untouched.
- The Network tab sends nothing. It reads how many bytes your Mac's network
  interfaces have moved, never what the bytes were, where they went, or which
  app moved them, and keeps the totals by the hour in
  `~/Library/Application Support/OpenNotch/network.sqlite` on this Mac only.
  The first time it runs, it reads NetSpeed's history from
  `~/Library/Application Support/NetSpeed` if it's there. **Clear History** in
  Settings › Network deletes it, and turning the tab off stops counting.
- Messages sent with the Show in Notch action or an `ilovenotch://` link are
  only displayed: they're never stored, and nothing in them is opened.
- Clipboard history is off until you turn it on in the Clipboard tab. Then it
  keeps what you copy (text, links, images, and file locations) in
  `~/Library/Application Support/OpenNotch` on this Mac only, up to 200 items
  plus your favorites. It skips anything the copying app marks secret or
  temporary and anything copied in a password manager. **Clear History**
  removes everything but favorites, and turning it off stops reading the
  clipboard.
- To move the media waveform with the music, ILoveNotch listens to your Mac's
  audio output, and macOS asks for "system audio recording" permission the first
  time. It listens only while the Media tab is open and something plays, turns
  the sound into loudness per frequency band as it plays, and never records,
  stores, or sends audio. Turn it off in Settings › Media.
- Shuffle, repeat, Music's up next and lyrics, Spotify's recently played, and,
  in the App Store edition, all of Media's controls talk to Music or Spotify
  through their own AppleScript, on this Mac. macOS asks first (Privacy &
  Security › Automation), the first time you press one of those buttons, and
  ILoveNotch only ever talks to the app that's playing. Spotify's recently
  played list is kept in memory and gone when ILoveNotch quits.
- An app you turn down in the Sound tab (GitHub build) plays through
  ILoveNotch at its new volume while it plays, on the same permission; one you
  mute is silenced at its source. Its sound goes straight back out to your
  speakers or headphones and is never recorded, stored, or sent. Apps you leave
  at 100% aren't touched. **Reset All** in Settings › Sound hands
  every app back its own volume. Switching devices and setting the output's or
  microphone's volume there hear nothing at all.

## AI Usage

The AI Usage tab shows how much of your AI coding plans you've used. Its
providers come from [OpenUsage](https://github.com/robinebers/openusage). Every
provider is off until you turn it on, and nothing reaches the network before
that.

To find which tools are signed in on this Mac, when you open the tab or its
settings, and to read a provider's sign-in when it refreshes, ILoveNotch:

- Reads the sign-in each tool keeps on this Mac: its files (like
  `~/.codex/auth.json` or Cursor's settings database) and its keychain items,
  through `/usr/bin/security`. The sign-ins stay in memory. macOS may ask you
  to allow a keychain read.
- May run your login shell once (`$SHELL -ilc env`) to see settings and API
  keys you export there, such as `CLAUDE_CONFIG_DIR` or `OPENROUTER_API_KEY`.
  Only non-secret settings (config folders, sign-in endpoints) are remembered.
- Keeps an API key you paste in **Settings › AI Usage** (for OpenRouter or
  Z.ai) in your login keychain, as "ILoveNotch AI Usage", never in a file.
  **Remove** there deletes it.

For each provider you turn on, ILoveNotch:

- Sends your sign-in only to that provider's own service, to ask for your
  usage. Antigravity is asked through its language server on this Mac, found
  with `ps` and `lsof`.
- When a sign-in has expired, renews it with that provider and saves the new
  token back where its tool keeps it, the same way the tool would. For
  Antigravity, it asks you to open Antigravity instead.
- Reads the tool's local session logs (Claude Code, Codex, and others) to
  estimate what you've spent. Prices come from public price lists: LiteLLM
  (raw.githubusercontent.com), models.dev, and OpenUsage's price supplement
  (robinebers.github.io). ILoveNotch downloads them about once an hour while a
  provider refreshes. These requests carry nothing about you or your usage.

Refreshes happen when you open the tab, every five minutes while it stays open,
and in the background only if you choose an interval in Settings (off by
default). Results are cached in `~/Library/Application Support/OpenNotch/` so
the tab paints at once. Turning a provider off deletes its cached results. The
Mac App Store edition doesn't include the AI Usage tab.

## Agent status

Agent status is off until you connect a tool in the Agents tab or in
**Settings › Agents**. Connecting adds hooks to that tool's own
settings file (`~/.claude/settings.json` for Claude Code, `~/.codex/hooks.json`
for Codex) and first keeps a copy of the file as it was in
`~/Library/Application Support/OpenNotch/Backups`. The hooks run a small script,
`~/Library/Application Support/OpenNotch/ilovenotch-agent-hook`, which writes one
file per session into `~/Library/Application Support/OpenNotch/Agents`: the
session's state, its project folder, the app it runs in, its process ID, and
the tool's own words for what it's waiting for. Your prompts, code, and tool
output are never written, and nothing leaves your Mac. Disconnecting removes the
hooks, and with no tool connected, the script and the session files too.

## Sharing with Android

Sharing with Android phones (Quick Share, in the shelf) uses your local network
only: phone and Mac talk directly over your Wi-Fi, never through the internet
or a server, and every connection is end-to-end encrypted.

- **Visible only when you choose.** Receiving is off until you turn it on: for
  10 minutes from the shelf, while the notch is open, or always. While it's on,
  your Mac announces itself to devices on the same network with the name you
  set in **Settings › Shelf** (your Mac's name unless you change it)
  and a random ID that changes each launch. Asleep or locked, it announces
  nothing.
- **Nothing without your consent.** A phone that connects shows its name, what
  it's sending, and a code matching its own, and nothing is saved until you
  accept. Files go to the folder you choose (Downloads unless you change it),
  marked as downloaded, as AirDrop marks files, so macOS checks any app or
  script among them before it runs. Text and links go to the clipboard; a link
  opens only when you click **Open**.
- **Looking for phones only while you send.** The send window looks for phones
  nearby while it's open and stops when it closes. Its QR code holds a key made
  for that window alone.

ILoveNotch keeps nothing about the phones it meets. macOS asks once for Local
Network access; turning it off in **System Settings › Privacy & Security ›
Local Network** turns this feature off and nothing else.

A change that weakens any of these points must say so in its pull request and
update this file.
