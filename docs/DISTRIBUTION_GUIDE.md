# LiquidDynamo — Public macOS Distribution, Signing & Notarization Guide

This guide details the complete end-to-end process for packaging, Developer ID codesigning, Apple notarization, stapling, and distribution of **LiquidDynamo** on macOS 14.0+.

Following this guide guarantees that any user downloading `LiquidDynamo.dmg` in a web browser can drag the application to `/Applications`, launch it, and experience **zero Gatekeeper malware alerts** ("Apple could not verify it is free of malware"), without needing "Open Anyway" or Terminal quarantine workarounds (`xattr -dr com.apple.quarantine`), even when offline.

---

## 1. Distribution & Architecture Overview

| Dimension | Value / Setting | Distribution Impact |
| :--- | :--- | :--- |
| **Distribution Channel** | Direct Distribution (Outside Mac App Store) | Required for hardware display DDC, global media keys (`CGEventTap`), and CPU thermal reading. |
| **Bundle Identifier** | `com.agrigence.liquiddynamo` | Unique bundle identity registered in Apple Developer portal. |
| **XPC Helper Identifier** | `com.agrigence.liquiddynamo.LiquidDynamoXPCHelper` | Privileged helper for hardware sensor access and display management. |
| **Hardened Runtime** | `ENABLE_HARDENED_RUNTIME = YES` (`flags=0x10000(runtime)`) | **Mandatory** for Apple Notarization. Protects against code injection and memory corruption. |
| **Entitlements** | `liquiddinamo/LiquidDynamo.entitlements` | Non-sandboxed (`app-sandbox = false`) with `disable-library-validation = true` for dylibs. |
| **Debug Entitlement** | `com.apple.security.get-task-allow` | **Safely absent** from Release builds. (Presence causes immediate Apple Notary rejection). |
| **Target Architectures** | Apple Silicon (`arm64`) & Universal | Native execution on Apple Silicon (M1/M2/M3/M4) and Intel Macs. |

---

## 2. Apple Developer Account Prerequisites

The agent or CI runner cannot perform these steps for you. Complete this short checklist once on your Mac:

### 1. Apple Developer Program Membership
- An active paid Apple Developer Program account ($99/year) is required at [developer.apple.com](https://developer.apple.com). Free Apple IDs cannot generate Developer ID certificates.

### 2. Developer ID Application Certificate
- Open **Xcode** > **Settings** (or **Preferences**) > **Accounts**.
- Select your Apple ID, choose your Team, and click **Manage Certificates...**.
- Click the **+** (plus) button in the bottom left corner and select **Developer ID Application**.
- Confirm that the certificate is installed in your macOS Keychain:
  ```bash
  security find-identity -v -p codesigning | grep "Developer ID Application"
  ```
  Expected output:
  ```text
  1) 1234567890ABCDEF... "Developer ID Application: Your Name (TEAMID)"
  ```

### 3. Store Notarytool Keychain Profile
- Generate an App-Specific Password at [account.apple.com](https://account.apple.com) under **Sign-In and Security** > **App-Specific Passwords**.
- Store the credentials securely in your macOS Keychain using `notarytool`:
  ```bash
  xcrun notarytool store-credentials "LIQUIDDYNAMO_NOTARY" \
    --apple-id "your-apple-id@example.com" \
    --team-id "YOUR_TEAM_ID" \
    --password "xxxx-xxxx-xxxx-xxxx"
  ```
- Test and verify connection:
  ```bash
  xcrun notarytool history --keychain-profile LIQUIDDYNAMO_NOTARY
  ```

---

## 3. The Professional Packaging & Signing Pipeline

The packaging workflow is automated by [`build_dmg.sh`](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/build_dmg.sh).

### Inside-Out Signing Hierarchy
Apple Notarization strictly inspects every Mach-O binary in the bundle. Signing must be performed **inside-out** so outer digital seals remain intact:
1. **Standalone executables in Resources**: `Contents/Resources/MediaRemoteAdapterTestClient`
2. **Individual Dynamic Libraries**: `Contents/Frameworks/*.dylib`
3. **Nested Framework XPC Services**: `Sparkle.framework/Versions/B/XPCServices/*.xpc`
4. **Nested Framework Helper Apps**: `Sparkle.framework/Versions/B/Updater.app`
5. **Nested Framework Executables**: `Sparkle.framework/Versions/B/Autoupdate`
6. **Framework Bundles**: `Sparkle.framework`, `Lottie.framework`, `MediaRemoteAdapter.framework`
7. **Top-Level XPC Services**: `Contents/XPCServices/LiquidDynamoXPCHelper.xpc` (signed with `LiquidDynamoXPCHelper.entitlements`)
8. **Main App Bundle**: `LiquidDynamo.app` (signed with `LiquidDynamo.entitlements`)

All signatures are applied with `--force --options runtime --timestamp --sign "$SIGN_IDENTITY"`.

### Two-Stage Notarization & Offline Stapling
To allow offline usage without Gatekeeper network lookups:
1. **Stage 1 (App Bundle)**:
   - Package `.app` into a temporary zip: `ditto -c -k --keepParent LiquidDynamo.app LiquidDynamo.zip`.
   - Submit zip to notary service: `xcrun notarytool submit LiquidDynamo.zip --keychain-profile LIQUIDDYNAMO_NOTARY --wait`.
   - On Accepted, staple ticket directly to the `.app`: `xcrun stapler staple LiquidDynamo.app`.
2. **Stage 2 (DMG Container)**:
   - Create disk image containing the stapled `.app` and custom folder presentation.
   - Sign the DMG: `codesign --force --timestamp --sign "$SIGN_IDENTITY" LiquidDynamo.dmg`.
   - Submit DMG to notary service: `xcrun notarytool submit LiquidDynamo.dmg --keychain-profile LIQUIDDYNAMO_NOTARY --wait`.
   - On Accepted, staple ticket to the DMG: `xcrun stapler staple LiquidDynamo.dmg`.

---

## 4. Release Commands

### Production Distribution Release Build
```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="LIQUIDDYNAMO_NOTARY" \
RELEASE=1 bash build_dmg.sh
```

### Local Test Build (Ad-hoc)
```bash
# Creates an ad-hoc local build for testing on this machine only
bash build_dmg.sh
```

---

## 5. Verification: `verify_release.sh`

Always verify your built release artifact before publishing:
```bash
bash scripts/verify_release.sh ~/Desktop/LiquidDynamo-2.0.5.dmg
```

### Checks Performed by `verify_release.sh`:
- ✅ Deep code signature validity (`codesign --verify --deep --strict`).
- ✅ Developer ID Application authority and Team ID verification.
- ✅ Hardened Runtime enabled (`flags=0x10000(runtime)`).
- ✅ Secure Apple Timestamp embedded on all Mach-Os and DMG.
- ✅ Gatekeeper assessment (`spctl -a -vvv -t install` on DMG / `-t exec` on `.app`) yields `source=Notarized Developer ID`.
- ✅ Apple Notarization staple ticket validation (`xcrun stapler validate`).
- ✅ Scan of all embedded Mach-O binaries (zero unsigned binaries).
- ✅ Safety check: `com.apple.security.get-task-allow` is absent.

---

## 6. Notarization Troubleshooting Reference

If Apple Notary Service returns `status: Invalid`, `build_dmg.sh` automatically fetches and displays the failure log (`xcrun notarytool log <id>`). Consult this reference for common causes and fixes:

| Failure Message / Symptom | Root Cause | Fix / Solution |
| :--- | :--- | :--- |
| `The binary is not signed with a valid Developer ID certificate.` | Built with `Apple Development`, `Mac Developer`, or ad-hoc `-`. | Use `Developer ID Application: <Name> (<TeamID>)`. |
| `The executable does not have the hardened runtime enabled.` | Missing `--options runtime` or `ENABLE_HARDENED_RUNTIME = NO`. | `build_dmg.sh` signs with `--options runtime`. Verify `project.pbxproj` has `ENABLE_HARDENED_RUNTIME = YES`. |
| `The signature does not include a secure timestamp.` | Missing `--timestamp` during signing. | Never omit `--timestamp`. `build_dmg.sh` includes `--timestamp` automatically. |
| `The signature of the binary is invalid.` | Out-of-order signing or modified files after signing. | Sign inside-out; never modify files inside `.app` after signing. |
| `The executable requests the com.apple.security.get-task-allow entitlement.` | Debug entitlement accidentally included in Release export. | Verify `get-task-allow` is not in `LiquidDynamo.entitlements` and configuration is `Release`. |
| `A nested binary was not signed.` | An embedded binary (e.g. `MediaRemoteAdapterTestClient` in Resources) was skipped. | `build_dmg.sh` scans and signs all embedded Mach-O binaries deepest first. |
| `No Keychain password item found for profile.` | Profile not created with `store-credentials`. | Run `xcrun notarytool store-credentials "LIQUIDDYNAMO_NOTARY"` with your App-Specific Password. |
| `Authentication failed (status code 401).` | Invalid Apple ID, Team ID, or expired App-Specific Password. | Generate a fresh App-Specific Password at [account.apple.com](https://account.apple.com) and update profile. |

---

## 7. Software Updates & Sparkle Status

- **Primary Update Mechanism**: LiquidDynamo uses a direct GitHub Releases update mechanism via `GitHubUpdateChecker.swift` pointing to `https://api.github.com/repos/anksarvesh-lgtm/dynamo-mac/releases/latest`.
- **Sparkle Framework**: Embedded for optional AppCast compatibility. To prevent accidental upstream checks, `SUFeedURL` and `SUPublicEDKey` are kept unset in `Info.plist`, which ensures Sparkle remains inactive until you generate your own EdDSA key pair and host your own signed `appcast.xml`.
- When publishing an update, both the zip archive and the DMG must be notarized and stapled.
