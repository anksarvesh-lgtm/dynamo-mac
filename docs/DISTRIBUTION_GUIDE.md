# LiquidDynamo — Public macOS Distribution & Notarization Guide

This guide describes the complete release, signing, notarization, and distribution process for **LiquidDynamo** on macOS 14.0+.

---

## 1. Distribution Readiness Audit

| Configuration | Value | Purpose / Impact |
| :--- | :--- | :--- |
| **Bundle Identifier** | `com.agrigence.liquiddynamo` | Unique app identity registered with Apple Developer portal. |
| **Deployment Target** | macOS 14.0 (Sonoma) or newer | Required for modern SwiftUI, continuous squircles, and Metal shaders. |
| **Architecture** | `arm64` / Universal | Optimized natively for Apple Silicon (M1/M2/M3/M4) MacBooks. |
| **Hardened Runtime** | `ENABLE_HARDENED_RUNTIME = YES` | Mandatory requirement for Apple Notarization (`notarytool`). |
| **Entitlements** | `liquiddinamo/LiquidDynamo.entitlements` | Non-sandboxed (Direct Distribution) allowing Accessibility key tap, display DDC/CI, and sensor queries. |
| **XPC Helper** | `com.agrigence.liquiddynamo.helper` | Handles privileged brightness and hardware sensor calls. |

---

## 2. Direct Distribution vs. Mac App Store

### Why Direct Distribution (Developer ID) is Required
LiquidDynamo relies on:
1. **Accessibility (`AXIsProcessTrusted`) & CGEventTap**: Captures media keys and trackpad gestures.
2. **IOKit / Private Frameworks (`DisplayServices`, `IOHIDEventSystemClient`)**: Reads hardware display brightness and Apple Silicon CPU die thermal sensors directly without requiring third-party kernel extensions or SIP bypass.
3. **CoreMediaIO (`CMIOObjectGetPropertyData`)**: Passive hardware sensor state detection (camera/mic active glow) without capturing actual video streams.

> [!IMPORTANT]
> Because the Mac App Store sandbox strictly prohibits `CGEventTap` global monitoring and direct `IOHIDEventSystem` sensor access, **Direct Distribution signed with Developer ID Application is the recommended and primary release path**.

---

## 3. Apple Developer Prerequisites

To distribute LiquidDynamo outside the Mac App Store without triggering Gatekeeper blocking alerts:

1. **Apple Developer Program Account**: Active membership at [developer.apple.com](https://developer.apple.com).
2. **Developer ID Application Certificate**:
   - Certificate Name: `Developer ID Application: <Your Team Name> (<Team ID>)`
   - Installed in your macOS Keychain (`login.keychain-db`).
3. **App-Specific Password / App Store Connect API Key**:
   - Create an App-Specific Password at [appleid.apple.com](https://appleid.apple.com), or generate an App Store Connect API Key (recommended for CI/CD).

---

## 4. Setting Up `notarytool` Keychain Credentials

Store your Apple Developer credentials securely in the macOS Keychain (never hardcode passwords or private keys in the repository):

```bash
xcrun notarytool store-credentials "LIQUIDDYNAMO_NOTARY" \
  --apple-id "your-apple-id@email.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

Verify that the profile is saved:
```bash
xcrun notarytool credentials-history
```

---

## 5. Building, Packaging, and Signing

The repository provides an automated, self-contained release script: [`build_dmg.sh`](file:///Users/sarvesh/Documents/LiquidDynamo-with-brain/build_dmg.sh).

### Step 5.1: Build Release Package

To create an ad-hoc local test build:
```bash
bash build_dmg.sh
```

To create a signed, production-ready build for Apple Notarization:
```bash
SIGN_IDENTITY="Developer ID Application: Your Company (TEAM_ID)" \
NOTARY_PROFILE="LIQUIDDYNAMO_NOTARY" \
bash build_dmg.sh
```

### What `build_dmg.sh` Performs Automatically:
1. Cleans and builds `LiquidDynamo` in `Release` configuration with Hardened Runtime enabled.
2. Signs nested code:
   - Frameworks in `Contents/Frameworks/*.framework`
   - XPCServices in `Contents/XPCServices/*.xpc`
3. Signs the main application bundle with `LiquidDynamo.entitlements` and `--options runtime`.
4. Validates deep code signature with `codesign --verify --deep --strict --verbose=2`.
5. Stages the disk image with `LiquidDynamo.app`, `/Applications` symlink, `.VolumeIcon.icns`, and custom window geometry.
6. Compresses the DMG using `hdiutil convert -format UDZO`.
7. Submits the DMG to Apple Notary Service via `xcrun notarytool submit --wait`.
8. Staples the notarization ticket to the DMG using `xcrun stapler staple`.

---

## 6. Verifying Notarization & Gatekeeper Compliance

Once the DMG is built and stapled, verify Gatekeeper acceptance:

```bash
# 1. Assess with Gatekeeper
spctl -a -vvv -t install ~/Desktop/LiquidDynamo-1.9.1.dmg

# 2. Check stapled ticket
xcrun stapler validate ~/Desktop/LiquidDynamo-1.9.1.dmg
```

Expected output:
```
source=Notarized Developer ID
accepted
```

---

## 7. End-User Installation & Permission Instructions

When users install LiquidDynamo:
1. Open `LiquidDynamo-1.9.1.dmg`.
2. Drag `LiquidDynamo` into the `Applications` folder.
3. Launch `LiquidDynamo` from `/Applications`.
4. Follow the setup assistant to enable requested permissions:
   - **Accessibility**: Enables media key HUD and volume gestures.
   - **Bluetooth**: Enables battery reporting and peripheral device identification.
   - **Camera / Mic**: Optional quick mirror and localized notch privacy glow.
