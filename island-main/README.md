# Island

**The iPhone Dynamic Island, recreated natively for the Mac notch.**

Island is one continuous surface that lives in your MacBook's notch. Live activities such as music, timers, downloads, and mic/camera use appear there in a compact form. Hover to expand the same object into an interactive surface, then let it settle back into the notch.

- **Native**: Swift, SwiftUI, and AppKit. No Electron, about 0.1% CPU when idle.
- **One island**: one primary activity plus up to two minimal bubbles, ordered by priority.
- **Universal media**: Apple Music, Spotify, VLC, and (opt-in) Safari, Chrome, Brave, and Edge media.
- **Liquid Glass** on macOS 26+, with full support for Reduce Motion, Reduce Transparency, and Increase Contrast.
- **Search** (⌥Space): apps, files, actions, web results, and optional AI answers with citations, all inside the island.
- Public Apple APIs only. No private frameworks, injection, or fake data.

## Install

Download **Island.dmg** from [Releases](https://github.com/poshak2004/island/releases), drag Island to Applications, and open it.
Island isn't notarized (no paid Apple Developer account), so the first launch needs **System Settings → Privacy & Security → Open Anyway**. See [DISTRIBUTION.md](DISTRIBUTION.md).

Requires macOS 14 Sonoma or later. Works on notched MacBooks, Macs without a notch, and external displays.

## Activities

| Activity | Compact | Source |
|---|---|---|
| Media | artwork · title · ▶ | Music / Spotify notifications + their AppleScript dictionaries; VLC; browser (opt-in) |
| Timer | ⏱ 24:32 | built-in (Island or search: `timer 20 min`) |
| Download | ↓ 72% | file progress published to ~/Downloads (Safari, Chrome, Finder) |
| Mic / camera in use | ● 02:31 | CoreAudio / CoreMediaIO "running somewhere" |
| Battery | ⚡ 84% | IOKit power-source notifications |
| Devices | AirPods connected | CoreAudio default-output changes |
| Network | Offline / Online | NWPathMonitor |
| Calendar | next event | EventKit (opt-in) |
| Clipboard | Copied … | local only (opt-in) |

Priority is deterministic: `critical > high > normal > low`. An activity of equal priority never steals focus from the current one. When an interruption (like a finished timer) is dismissed, the previous activity returns.

## Build from source

```sh
scripts/test.sh            # unit tests + headless app self-test
scripts/run.sh --demo      # build, bundle and launch with demo activities
scripts/build-release.sh   # universal dist/Island.app
scripts/package-release.sh # dist/Island.zip, Island.dmg, SHA256SUMS.txt
```

Only the Xcode Command Line Tools are needed. See [DEVELOPMENT.md](DEVELOPMENT.md).

## Docs

[ARCHITECTURE](ARCHITECTURE.md) · [DESIGN](DESIGN.md) · [DEVELOPMENT](DEVELOPMENT.md) · [DISTRIBUTION](DISTRIBUTION.md) · [PRIVACY](PRIVACY.md) · [ROADMAP](ROADMAP.md)

## License

[MIT](LICENSE)
