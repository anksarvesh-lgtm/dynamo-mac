# Distribution

Island is distributed free through GitHub Releases. It is **ad-hoc signed** (`codesign -s -`) and **not notarized**, because notarization requires a paid Apple Developer account.

## Opening Island the first time

macOS blocks apps from unidentified developers on first launch. This is the normal, per-app way to allow one:

1. Move **Island.app** to **Applications** and double-click it. macOS says it can't verify the developer. Click **Done**.
2. Open **System Settings → Privacy & Security**.
3. Scroll to Security, find *"Island" was blocked to protect your Mac*, and click **Open Anyway**.
4. Confirm with your password or Touch ID, then click **Open**.

You only do this once per version. **Don't disable Gatekeeper globally**; it isn't needed.

## Verify your download

```sh
shasum -a 256 Island.dmg   # compare with SHA256SUMS.txt from the release
codesign -dv /Applications/Island.app
```

## Permissions Island may ask for

| Prompt | When | Why |
|---|---|---|
| Automation → Music / Spotify / VLC / browser | first time that app plays | read now-playing info and send play/pause/skip |
| Calendars | only if you enable Calendar | show your next event |
| Accessibility | only if you use media keys with no supported player | send the system play/pause key |
| Downloads folder | possibly when a download finishes | show its name and offer Open / Show in Finder |

## Building releases

`scripts/build-release.sh <version>` builds `dist/Island.app` (universal). `scripts/package-release.sh` then produces `Island.zip` (via `ditto`), `Island.dmg` and `SHA256SUMS.txt`. CI does the same on every tag `v*`.
