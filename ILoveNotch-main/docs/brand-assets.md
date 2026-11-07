# Brand assets

The design files the app and its listings use, with the exact files and sizes. Make them in any
tool, put them in a `Brand/` folder at the repository root with the names below, and open a pull
request (or hand the folder over). The code side (asset catalog, `project.yml`, the About screen,
the menu bar item, the DMG) is wired up from these files, so nothing else needs editing.

**Done:** the name, ILoveNotch; the app icon, in `App/Assets.xcassets/AppIcon.appiconset` and on
the About screen; nine 1440 × 900 marketing screenshots, six of them in the README. **Still
wanted:** the menu bar icon (section 3), the logo SVGs (4), the social preview (5), the DMG
background (6), the accent colors (1), and optionally a layered Icon Composer icon (2).

## 1. Name and identity

| Item | Format | Notes |
|------|--------|-------|
| Product name | text, 30 characters max | Must be unique on the Mac App Store. |
| Subtitle | text, 30 characters max | One line under the name on the App Store and in the README. |
| Bundle ID | reverse DNS, for example `com.niyamvora.notch` | Permanent once published. The current one is `cafe.opennotch.app`. |
| Accent color | hex, one for light and one for dark | Tints selection, buttons, and links. |

Put the text in `Brand/brand.json`:

```json
{
  "name": "…",
  "subtitle": "…",
  "bundleID": "com.example.notch",
  "accent": { "light": "#RRGGBB", "dark": "#RRGGBB" }
}
```

## 2. App icon

| File | Size | Notes |
|------|------|-------|
| `Brand/icon/AppIcon.icon` | Icon Composer document | Preferred. The layered Liquid Glass icon for macOS 26 (Xcode 26 › Open Developer Tool › Icon Composer). |
| `Brand/icon/AppIcon-1024.png` | 1024 × 1024 px, sRGB | Flattened master for macOS 14 and 15, the DMG, the website, and the App Store. Follow Apple's macOS icon grid: the rounded-rectangle body sits inside the canvas with transparent corners and room for the shadow. |
| `Brand/icon/AppIcon.appiconset/icon_16x16.png` | 16 × 16 px | Every size exported from the master. Small sizes may need simplified detail to stay legible. |
| `…/icon_16x16@2x.png` | 32 × 32 px | |
| `…/icon_32x32.png` | 32 × 32 px | |
| `…/icon_32x32@2x.png` | 64 × 64 px | |
| `…/icon_128x128.png` | 128 × 128 px | |
| `…/icon_128x128@2x.png` | 256 × 256 px | |
| `…/icon_256x256.png` | 256 × 256 px | |
| `…/icon_256x256@2x.png` | 512 × 512 px | |
| `…/icon_512x512.png` | 512 × 512 px | |
| `…/icon_512x512@2x.png` | 1024 × 1024 px | Same as the master. |

PNG, sRGB, no layers or color profiles other than sRGB. The App Store rejects builds without the
1024 px icon.

## 3. Menu bar icon

| File | Size | Notes |
|------|------|-------|
| `Brand/menubar/MenuBarIcon.svg` | 18 × 18 pt artboard, glyph about 16 pt | Preferred. A template image: pure black shapes on transparency, no color or gradients; macOS tints it for light, dark, and highlighted menu bars. |
| `Brand/menubar/MenuBarIcon.png` and `MenuBarIcon@2x.png` | 18 × 18 and 36 × 36 px | Only if an SVG isn't possible. |

It replaces the SF Symbol the menu bar item uses today and must read at a glance at 16 pt.

## 4. Logo

| File | Notes |
|------|-------|
| `Brand/logo/mark.svg` | The symbol on its own, without the icon's background. Used in Settings › About and the README. |
| `Brand/logo/wordmark.svg` | Symbol and name, dark on light backgrounds. |
| `Brand/logo/wordmark-dark.svg` | Light on dark backgrounds. |

## 5. GitHub and README

| File | Size | Notes |
|------|------|-------|
| `Brand/social/social-preview.png` | 1280 × 640 px, under 1 MB | The GitHub repository's social preview (link cards on X, Slack, iMessage). Keep important content inside the middle 1200 × 600. |
| `Brand/readme/hero.png` | 1600 × 900 px | The first image in the README: the notch open on a clean desktop. |
| `Brand/readme/hero.mp4` | 1600 × 900, 5–10 s, under 10 MB | Optional. The notch opening and switching tabs; a GIF made from it works too. |

## 6. DMG (downloads from GitHub Releases)

| File | Size | Notes |
|------|------|-------|
| `Brand/dmg/background.png` | 660 × 400 px | The window background when the DMG opens. Leave two clear spots for icons, centered at (180, 200) for the app and (480, 200) for the Applications folder, with an arrow between them. |
| `Brand/dmg/background@2x.png` | 1320 × 800 px | Retina version of the same. |

## 7. Mac App Store listing

| File | Size | Notes |
|------|------|-------|
| `Brand/app-store/screenshots/en-US/01-….png` | 2880 × 1800 px (or 2560 × 1600, 1440 × 900, 1280 × 800) | 1 to 10 screenshots, 16:10, PNG or JPEG without transparency. Suggested: media, shelf, calendar, tasks, notes, timer, settings. Framed marketing shots or plain captures both work; plain captures can be made from the app. |
| `Brand/app-store/preview.mov` | 1920 × 1080, 15–30 s | Optional app preview video. |

The listing text (description, keywords, promotional text, support and privacy URLs) is in
[docs/app-store](app-store/metadata.md). Version 1.0.0's listing is in App Store Connect with nine
designed screenshots and a 30-second preview.

## 8. Optional

| File | Notes |
|------|-------|
| `Brand/mascot/*.json` | A Lottie animation for onboarding or the changelog only, never in the always-visible notch. |
| Languages | A list of languages to localize into. Strings are extracted into a String Catalog in code; translations can be drafted and reviewed. |

No sounds are needed, and haptics use the system's own feedback.

## What the code does with them

- `AppIcon.icon` or `AppIcon.appiconset` becomes the app icon (asset catalog, `ASSETCATALOG_COMPILER_APPICON_NAME`).
- The accent colors become `AccentColor` in the asset catalog.
- `MenuBarIcon` becomes the status item's template image.
- `mark.svg` appears in Settings › About; the wordmarks and hero go in the README.
- The DMG backgrounds go into the release script's DMG layout.
- Screenshots and the listing text upload to App Store Connect.
