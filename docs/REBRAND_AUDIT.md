# LiquidDynamo Rebrand Audit & Migration Plan (Phase 1)

> **Status**: Phase 1 Audit Complete — Awaiting Approval  
> **Target Brand**: LiquidDynamo  
> **Developer / Organization**: Agrigence  
> **License**: GNU General Public License v3.0 (GPL-3.0)  
> **Date**: October 4, 2026  

---

## 1. Executive Summary & Legal Guardrails

This audit provides a comprehensive inventory of all occurrences of upstream brand names, URLs, identifiers, update feeds, and legal notices across the entire codebase.

### Strict Legal Rules & GPL-3.0 Compliance
1. **LICENSE & Header Integrity**: Boring Notch is licensed under **GPL-3.0**. The `LICENSE` file and existing author/copyright headers in all source files **must not** be deleted or modified.
2. **Attribution Boundaries**: Agrigence will never claim authorship of the original code. Modifications and new files carry `"Copyright © 2026 Agrigence"` alongside existing notices.
3. **The Three Upstream Attribution Locations**:
   - `LICENSE`: Preserved in full.
   - `NOTICE.md`: New file detailing origin, GPL-3.0 license, and fork date.
   - **"Open source licenses" modal/screen**: Accessible from the About screen in Settings.
   - *Upstream credit does not appear anywhere on the primary UI.*

---

## 2. Group A: User-Visible Hits

These items are directly seen, heard, or interacted with by end-users. All must be updated in Phase 2 to reflect **LiquidDynamo** and **Agrigence**.

| Component / File | Line(s) | Current Upstream Content | Proposed LiquidDynamo Replacement |
| :--- | :--- | :--- | :--- |
| **Menu Bar Extra**<br>`boringNotch/boringNotchApp.swift` | 32 | `MenuBarExtra("boring.notch", systemImage: "sparkle", ...)` | `MenuBarExtra("LiquidDynamo", systemImage: "sparkle", ...)` |
| **Menu Bar Restart Button**<br>`boringNotch/boringNotchApp.swift` | 41 | `Button("Restart Boring Notch")` | `Button("Restart LiquidDynamo")` |
| **Status Bar Menu**<br>`boringNotch/menu/StatusBarMenu.swift` | 14 | `accessibilityDescription: "BoringNotch"` | `accessibilityDescription: "LiquidDynamo"` |
| **Settings Window Title**<br>`boringNotch/components/Settings/SettingsWindowController.swift` | 43 | `window.title = "Boring Notch Settings"` | `window.title = "LiquidDynamo Settings"` |
| **About View Header & Credits**<br>`boringNotch/components/Settings/SettingsView.swift` | 1048 | `Text("Made with 🫶🏻 by not so boring not.people")` | Replace with `"LiquidDynamo by Agrigence"` and add `"Open source licenses"` button |
| **Settings / Extras GitHub Link**<br>`boringNotch/components/Settings/SettingsView.swift`<br>`boringNotch/components/Notch/BoringExtrasMenu.swift` | 1029<br>46 | Links to `https://github.com/TheBoredTeam/boring.notch` with `"GitHub"` / `"Checkout"` | Remove or replace with Agrigence repository link (per user preference) |
| **Shelf Settings Label**<br>`boringNotch/components/Settings/SettingsView.swift` | 1086 | `Defaults.Toggle(key: .boringShelf)` | Display as `"LiquidDynamo Shelf"` |
| **Mirror Settings Label**<br>`boringNotch/components/Settings/SettingsView.swift` | 1549 | `Text("Enable boring mirror")` | `Text("Enable mirror")` |
| **Welcome View Title**<br>`boringNotch/components/Onboarding/WelcomeView.swift` | 29 | `Text("Boring Notch")` | `Text("LiquidDynamo")` |
| **Welcome View Logo**<br>`boringNotch/components/Onboarding/WelcomeView.swift` | 24 | `Image("logo2")` (displays `BoringNotch icon.png`) | Replace with new LiquidDynamo asset |
| **Welcome View Watermark**<br>`boringNotch/components/Onboarding/WelcomeView.swift` | 65 | `Image("theboringteam")` (`TheBoringTeam.svg`) | Replace with Agrigence branding or remove |
| **Camera Permission Prompt**<br>`boringNotch/components/Onboarding/OnboardingView.swift` | 43 | `"Boring Notch includes a mirror feature..."` | `"LiquidDynamo includes a mirror feature..."` |
| **Calendar Permission Prompt**<br>`boringNotch/components/Onboarding/OnboardingView.swift` | 65 | `"Boring Notch can show all your upcoming events..."` | `"LiquidDynamo can show all your upcoming events..."` |
| **Reminders Permission Prompt**<br>`boringNotch/components/Onboarding/OnboardingView.swift` | 87 | `"Boring Notch can show your scheduled reminders..."` | `"LiquidDynamo can show your scheduled reminders..."` |
| **Accessibility Permission Prompt**<br>`boringNotch/components/Onboarding/OnboardingView.swift` | 109 | `"...with the Boring Notch HUD."` | `"...with the LiquidDynamo HUD."` |
| **Welcome Chime / Audio**<br>`boringNotch/boringNotchApp.swift` | 445 | `audioPlayer.play(fileName: "boring", fileExtension: "m4a")` | Replace audio file with LiquidDynamo chime or silence |
| **Localization Catalog**<br>`boringNotch/Localizable.xcstrings` | Keys & values | `"Boring Notch"`, `"boring.notch"`, `"Restart Boring Notch"`, `"Enable boring mirror"`, `"Made with 🫶🏻 by not so boring not.people"` | Update localized strings to `"LiquidDynamo"`, `"Restart LiquidDynamo"`, `"Enable mirror"`, etc. |
| **Target Display Name**<br>`boringNotch.xcodeproj/project.pbxproj` | 1469, 1523 | `INFOPLIST_KEY_CFBundleDisplayName = "Boring Notch"` | `INFOPLIST_KEY_CFBundleDisplayName = "LiquidDynamo"` |
| **Target CFBundleName**<br>`boringNotch.xcodeproj/project.pbxproj` | 1470, 1524 | `INFOPLIST_KEY_CFBundleName = "Boring Notch"` | `INFOPLIST_KEY_CFBundleName = "LiquidDynamo"` |
| **Target Product Name**<br>`boringNotch.xcodeproj/project.pbxproj` | 1486, 1540 | `PRODUCT_NAME = "Boring Notch"` | `PRODUCT_NAME = "LiquidDynamo"` |
| **DMG Packaging Volume Name**<br>`Configuration/dmg/dmgbuild_settings.py` | 10 | `VOLUME_NAME = os.environ.get('DMG_VOLUME_NAME', 'Boring Notch')` | `VOLUME_NAME = os.environ.get('DMG_VOLUME_NAME', 'LiquidDynamo')` |
| **DMG App Basename**<br>`Configuration/dmg/dmgbuild_settings.py`<br>`Configuration/dmg/create_dmg.sh` | 38<br>99 | `app_basename = 'Boring Notch.app'`<br>`Release/Boring Notch.app` | `app_basename = 'LiquidDynamo.app'`<br>`Release/LiquidDynamo.app` |

---

## 3. Group B: Network & External Endpoints

All network channels pointing to the original developer team must be eliminated or rerouted so that the application never pings upstream servers.

### B1. Update Feeds & Public Signing Keys
- **Upstream Feed URL**:
  - `boringNotch/Info.plist:15`: `<string>https://TheBoredTeam.github.io/boring.notch/appcast.xml</string>`
- **Upstream EdDSA Public Key**:
  - `boringNotch/Info.plist:17`: `<string>B1Y47t8C/v8ImurYA+9arEsuCrpxwJSviekiflMElbI=</string>`
- **Sparkle Services in Plist**:
  - `boringNotch/Info.plist:10-13`: `SUEnableDownloaderService`, `SUEnableInstallerLauncherService`
- **Upstream Appcast File**:
  - `updater/appcast.xml`: 639 lines referencing `https://github.com/TheBoredTeam/boring.notch/releases/download/...`
- **Action for Phase 2**: Remove `SUFeedURL` and `SUPublicEDKey` from `Info.plist`. In `boringNotchApp.swift` and `SettingsView.swift`, disable active update checks and hide/remove updater UI until Agrigence deploys its own appcast feed and signing key. Delete or decouple `updater/appcast.xml`.

### B2. Donation & Community Endpoints (To Remove/Decouple)
- **Ko-fi Donation**:
  - `.github/FUNDING.yml:2`: `ko-fi: alexander5015`
  - `README.md:16, 182`: `https://www.ko-fi.com/alexander5015`
- **Discord Community**:
  - `README.md:13, 162`: `https://discord.gg/GvYcYpAKTu`, `https://discord.gg/c8JXA7qrPm`
  - `CONTRIBUTING.md:129`: `https://discord.com/servers/boring-notch-1269588937320566815`
- **Original Project Website & Star Charts**:
  - `README.md:3, 175-177`: `http://theboring.name`, `https://raw.githubusercontent.com/TheBoredTeam/org-star-chart-updater/...`
  - `README.md:22`: `https://trendshift.io/repositories/14815`
- **Crowdin Localization Project**:
  - `README.md:11`: `https://crowdin.com/project/boring-notch`
  - `.github/PULL_REQUEST.md:7`: `https://crowdin.com/project/boring-notch`
- **GitHub Security Advisories**:
  - `SECURITY.md:7`: `https://github.com/TheBoredTeam/boring.notch/security/advisories/new`
- **Homebrew Tap**:
  - `README.md:98`: `brew install --cask TheBoredTeam/boring-notch/boring-notch`
  - `.github/workflows/release.yml:650`: `TheBoredTeam/homebrew-boring-notch`

### B3. Analytics / Telemetry Audit
- **Telemetry SDK Search**: A repository-wide audit for Firebase, Segment, TelemetryDeck, Mixpanel, Amplitude, Sentry, Crashlytics, and Google Analytics confirmed that **no telemetry or tracking SDKs are installed**.
- The only internal use of the word "telemetry" is local display of Wi-Fi metrics (dBm, SNR, channel band) in `WiFiInfoService.swift`.

### B4. Legitimate Functional Endpoints (Retained in App)
The following endpoints perform essential feature functionality and do **not** contact upstream developers:
1. **Meshy 3D Cloud Generation API**:
   - `boringNotch/Features/DeviceShowcase/MeshyImageTo3DProvider.swift:50`: `https://api.meshy.ai/openapi/v1/image-to-3d` (authenticated via user's private Keychain API key).
2. **Google Custom Search API**:
   - `boringNotch/Features/DeviceShowcase/ProductImageService.swift:119`: `https://www.googleapis.com/customsearch/v1` (for device image resolution).
3. **Public IP Verification Endpoint**:
   - `boringNotch/Features/Network/PublicIPService.swift:22`: `https://api64.ipify.org` (on-demand only).
4. **Apple networkQuality Speed Test**:
   - `boringNotch/Features/Network/SpeedTestService.swift`: Runs local `/usr/bin/networkQuality`, contacting Apple measurement CDN.
5. **LRCLIB Lyrics API**:
   - `boringNotch/managers/MusicManager.swift:425`: `https://lrclib.net/api/search` (open-source synced lyrics provider).
6. **Local Desktop Companion**:
   - `boringNotch/MediaControllers/YouTube Music Controller/YouTubeMusicModels.swift:18`: `http://localhost:26538` (local loopback communication only).
7. **Lottie Demo Animation**:
   - `boringNotch/components/Music/LottieAnimationView.swift:15`: `https://assets9.lottiefiles.com/packages/lf20_mniampqn.json`.

---

## 4. Group C: Identifiers

These technical identifiers register the application with macOS subsystem services, preference suites, Keychain, and XPC.

### C1. Bundle Identifiers
- **Main App Target**:
  - File: `boringNotch.xcodeproj/project.pbxproj` (lines 1485, 1539)
  - Current: `theboringteam.boringnotch`
  - **Proposed Replacement**: `com.agrigence.liquiddynamo` *(Awaiting confirmation)*
- **Helper XPC Target**:
  - File: `boringNotch.xcodeproj/project.pbxproj` (lines 1285, 1310)
  - Current: `theboringteam.boringnotch.BoringNotchXPCHelper`
  - **Proposed Replacement**: `com.agrigence.liquiddynamo.BoringNotchXPCHelper`

### C2. Login Item / Background Service
- **Framework**: `LaunchAtLogin-Modern` (`boringNotch/components/Settings/SettingsView.swift:162`)
- **Mechanism**: Calls macOS `SMAppService.mainApp`, registering the host app bundle identifier with macOS System Settings > General > Login Items.
- **Impact**: Changing the bundle ID to `com.agrigence.liquiddynamo` automatically causes Login Items to display "LiquidDynamo" under developer "Agrigence".

### C3. Keychain Service Names
- **Keychain Wrapper**: `boringNotch/Features/DeviceShowcase/KeychainService.swift`
- **Line 17**: `public static let defaultService = "theboringteam.boringnotch.apikeys"`
- **Proposed Replacement**: `"com.agrigence.liquiddynamo.apikeys"`

### C4. XPC Service Names
- **XPC Client**: `boringNotch/XPCHelperClient/XPCHelperClient.swift` (line 8)
- **XPC Protocol**: `boringNotch/XPCHelperClient/BoringNotchXPCHelperProtocol.swift` (line 28) and `BoringNotchXPCHelper/BoringNotchXPCHelperProtocol.swift` (line 28)
- **Current**: `theboringteam.boringnotch.BoringNotchXPCHelper`
- **Proposed Replacement**: `com.agrigence.liquiddynamo.BoringNotchXPCHelper`

### C5. Entitlements Match-Up
- **File**: `boringNotch/boringNotch.entitlements` (lines 30–31)
  ```xml
  <key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
  <array>
      <string>$(PRODUCT_BUNDLE_IDENTIFIER)-spks</string>
      <string>$(PRODUCT_BUNDLE_IDENTIFIER)-spki</string>
  </array>
  ```
  *(Dynamic expansion automatically tracks the new `PRODUCT_BUNDLE_IDENTIFIER`).*

### C6. User Settings & Defaults Keys
- **Settings Storage**: Standard `UserDefaults.standard` stores preferences in `~/Library/Preferences/<bundle-id>.plist`.
  - Upstream file: `~/Library/Preferences/theboringteam.boringnotch.plist`
  - LiquidDynamo file: `~/Library/Preferences/com.agrigence.liquiddynamo.plist`
  - **Important Notice**: Migrating to `com.agrigence.liquiddynamo` means existing user preferences will cleanly reset to defaults for the new brand.
- **Specific Key**:
  - `boringNotch/models/Constants.swift:194`: `static let boringShelf = Key<Bool>("boringShelf", default: true)`
  - Phase 2 change: Can remain or alias to `shelfEnabled` while keeping storage clean.

### C7. Application Support Directories & Local Paths
- **Shelf Storage**:
  - `boringNotch/components/Shelf/Services/ShelfPersistenceService.swift:24`: `.appendingPathComponent("boringNotch", isDirectory: true)`
  - Proposed: `.appendingPathComponent("LiquidDynamo", isDirectory: true)`
- **Device Model Cache Directory**:
  - `boringNotch/Features/DeviceShowcase/DeviceModelStore.swift:83`: `Bundle.main.bundleIdentifier ?? "theboringteam.boringnotch"`
  - Automatically migrates to `Application Support/com.agrigence.liquiddynamo/DeviceModels`.
- **Speed Test History Directory**:
  - `boringNotch/Features/Network/SpeedTestService.swift:121`: `Bundle.main.bundleIdentifier ?? "theboringteam.boringnotch"`
  - Automatically migrates to `Application Support/com.agrigence.liquiddynamo/SpeedTest`.

### C8. TipKit / AppIcon Lookup
- **File**: `boringNotch/components/Tips/TipStore.swift` (lines 23, 45)
- **Current**: `AppIcon(for: "theboringteam.boringNotch")`
- **Proposed**: `AppIcon(for: Bundle.main.bundleIdentifier ?? "com.agrigence.liquiddynamo")`

### C9. Dispatch Queues & Error Domains
- `WebcamManager.swift:38`: `label: "BoringNotch.WebcamManager.SessionQueue"` -> `label: "LiquidDynamo.WebcamManager.SessionQueue"`
- `WebcamManager.swift:170`: `domain: "BoringNotch.WebcamManager"` -> `domain: "LiquidDynamo.WebcamManager"`
- `WiFiInfoService.swift:322`: `theboringteam.boringnotch.wifi` -> `com.agrigence.liquiddynamo.wifi`
- `NetworkThroughputService.swift:65`: `theboringteam.boringnotch.throughput` -> `com.agrigence.liquiddynamo.throughput`
- `ConnectionStatusService.swift:91`: `theboringteam.boringnotch.connectionstatus` -> `com.agrigence.liquiddynamo.connectionstatus`
- `MultiDisplayBrightnessService.swift:47`: `theboringteam.boringnotch.ddc` -> `com.agrigence.liquiddynamo.ddc`
- `SystemStatsService.swift:46`: `theboringteam.boringnotch.systemstats` -> `com.agrigence.liquiddynamo.systemstats`

### C10. Notifications & Window Identifiers
- `SharingStateManager.swift:13`: `Notification.Name("com.boringNotch.sharingDidFinish")` -> `Notification.Name("com.agrigence.liquiddynamo.sharingDidFinish")`
- `SettingsWindowController.swift:58`: `NSUserInterfaceItemIdentifier("BoringNotchSettingsWindow")` -> `NSUserInterfaceItemIdentifier("LiquidDynamoSettingsWindow")`

### C11. App Groups & URL Schemes
- **App Groups**: None configured (no `com.apple.security.application-groups` entitlement).
- **Custom URL Schemes**: None registered in `Info.plist` (only system URL scheme routing in `ShelfItemViewModel.swift`).

---

## 5. Group D: Legally Required Notices (DO NOT TOUCH)

In strict accordance with the GNU General Public License v3.0, the following items **must remain untouched**:

1. **Root License File (`LICENSE`)**:
   - Contains the full, unmodified text of the GNU General Public License v3.0, June 2007 (Free Software Foundation).
   - Must remain at repository root.
2. **Third-Party Attribution File (`THIRD_PARTY_LICENSES`)**:
   - Contains attribution and license texts for:
     - `MediaRemoteAdapter` (BSD-3-Clause) — Jonas van den Berg & contributors.
     - `Calendr` (MIT License) — Carlos César Neves Enumo.
     - `DynamicNotchKit` (MIT License) — Kai Azim.
     - `NotchDrop` (MIT License) — Lakr Aream.
     - `Parrot` (Mozilla Public License 2.0) — Aditya Vaidyam & contributors.
3. **Source File Copyright & Author Headers**:
   - Header comments such as `Created by Richard Kunkli`, `Created by Harsh Vardhan Goswami`, `Created by Alexander`, and `Copyright © 2024 The Boring Team` must be preserved.
   - Per GPL-3.0 Section 5(a), new modifications may include:  
     `// Modified by Agrigence on October 4, 2026.`  
     `// Copyright © 2026 Agrigence. All rights reserved.`

---

## 6. Group E: Internal Code Identifiers (Recommendation: Leave Alone)

The following files and Swift structures contain the word "Boring" in their source code names:

### E1. Internal Swift Types
- `BoringViewModel` (`boringNotch/models/BoringViewModel.swift`)
- `BoringViewCoordinator` (`boringNotch/BoringViewCoordinator.swift`)
- `BoringHeader` (`boringNotch/components/Notch/BoringHeader.swift`)
- `BoringBatteryView` (`boringNotch/components/Live activities/BoringBattery.swift`)
- `BoringExtrasMenu` & `BoringLargeButtons` (`boringNotch/components/Notch/BoringExtrasMenu.swift`)
- `BoringNotchWindow` (`boringNotch/components/Notch/BoringNotchWindow.swift`)
- `BoringNotchSkyLightWindow` (`boringNotch/components/Notch/BoringNotchSkyLightWindow.swift`)
- `BoringStatusMenu` (`boringNotch/menu/StatusBarMenu.swift`)
- `BoringAnimations` (`boringNotch/animations/drop.swift`)
- `BoringNotchXPCHelper` (`BoringNotchXPCHelper/BoringNotchXPCHelper.swift`)

### E2. File & Directory Names
- `boringNotch/boringNotchApp.swift`
- `boringNotch/BoringViewCoordinator.swift`
- `boringNotch/models/BoringViewModel.swift`
- `boringNotch/components/Notch/BoringHeader.swift`
- `boringNotch/components/Notch/BoringNotchWindow.swift`
- `boringNotch/components/Notch/BoringExtrasMenu.swift`
- `boringNotch/components/Notch/BoringNotchSkyLightWindow.swift`
- `boringNotch/components/Calendar/BoringCalendar.swift`
- `boringNotch/components/Live activities/BoringBattery.swift`
- `boringNotch/boringNotch.entitlements`
- `boringNotch.xcodeproj`
- `BoringNotchXPCHelper/` directory

### E3. Recommendation: Leave Alone for Now
We strongly recommend **leaving these internal identifiers unchanged** in this rebrand pass for the following technical reasons:
1. **Zero User Visibility**: Swift type names and file paths are never exposed in the compiled binary, Dock, Activity Monitor, menu bar, or Settings UI.
2. **Git History & Blame Preservation**: Renaming dozens of core files creates massive diffs and complicates tracking upstream improvements.
3. **Xcode Project & SPM Stability**: Renaming the Xcode project or targets risks invalidating file references, build schemes, and synchronized folder mappings.
4. **Focused Scope**: Adheres strictly to the user prompt instruction: *"Do not rename internal classes, files, or the Xcode project in this pass."*

---

## 7. Required Artwork & Asset Inventory for User

Per Step 6 of Phase 2, the following artwork and assets must be supplied by the user (no placeholder artwork will be automatically generated):

### 1. App Icon Set (`boringNotch/Assets.xcassets/AppIcon.appiconset/`)
Supply PNG assets in the following pixel dimensions:
| Size (Points) | Scale | Required Pixel Dimensions | Target Filename |
| :--- | :--- | :--- | :--- |
| 16 x 16 pt | 1x | **16 x 16 px** | `icon_16x16.png` |
| 16 x 16 pt | 2x | **32 x 32 px** | `icon_16x16@2x.png` |
| 32 x 32 pt | 1x | **32 x 32 px** | `icon_32x32.png` |
| 32 x 32 pt | 2x | **64 x 64 px** | `icon_32x32@2x.png` |
| 128 x 128 pt | 1x | **128 x 128 px** | `icon_128x128.png` |
| 128 x 128 pt | 2x | **256 x 256 px** | `icon_128x128@2x.png` |
| 256 x 256 pt | 1x | **256 x 256 px** | `icon_256x256.png` |
| 256 x 256 pt | 2x | **512 x 512 px** | `icon_256x256@2x.png` |
| 512 x 512 pt | 1x | **512 x 512 px** | `icon_512x512.png` |
| 512 x 512 pt | 2x | **1024 x 1024 px** | `icon_512x512@2x.png` |

### 2. Branding Images (`boringNotch/Assets.xcassets/`)
| Asset Name | Current Dimensions | Description / Usage | Target Format |
| :--- | :--- | :--- | :--- |
| `logo2` | 1024 x 1024 px | Primary high-res logo displayed on the Welcome screen (`WelcomeView.swift:24`) | PNG (1024 x 1024 px) |
| `logo` | 256 x 256 px | Secondary icon asset used in HUD and notifications | PNG (256 x 256 px) |
| `theboringteam` | Vector SVG | Developer signature watermark at the bottom of `WelcomeView.swift:65` | SVG (or replacement Agrigence watermark) |

### 3. DMG Installer Window Background (`Configuration/dmg/.background/`)
| Asset | Current Dimensions | Description | Target Format |
| :--- | :--- | :--- | :--- |
| `background.tiff` | 660 x 400 pt (1320 x 800 px @2x) | DMG installer drag-to-Applications window background | Multi-representation TIFF or HiDPI PNG |

### 4. Audio Chime (`boringNotch/`)
| Asset | Current Format | Description | Target Format |
| :--- | :--- | :--- | :--- |
| `boring.m4a` | M4A audio | Welcome chime played on first setup (`boringNotchApp.swift:445`) | M4A / AAC audio (or can be silenced/removed) |

---

## 8. Questions for User Approval Before Phase 2

Before executing Phase 2 changes, please confirm the following:

1. **Bundle Identifier Confirmation**:  
   Do you confirm `com.agrigence.liquiddynamo` as the main app bundle ID, and `com.agrigence.liquiddynamo.BoringNotchXPCHelper` as the helper ID?
2. **Community & Donation Links**:  
   Would you like the GitHub / Ko-fi / Discord links completely removed from the UI, or replaced with specific Agrigence links?
3. **Welcome Audio Chime**:  
   Should we silence `playWelcomeSound()` or would you like to provide an alternative audio file?
