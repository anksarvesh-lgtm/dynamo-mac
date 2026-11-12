# HUD Interception & Hardware Control Behavioral Specification

This document specifies the behavioral state machine, key-interception safety contract, hardware control verification rules, and visual readout formatting for system HUDs and hardware controllers in LiquidDynamo.

---

## 1. Key Event Decoding

System media and brightness keys arrive as macOS system-defined events with subtype `8`. A packed 32-bit `data1` integer encodes both the key code and the transition state:

- **Key code**: upper 16 bits (`(data1 & 0xFFFF_0000) >> 16`).
- **Key state**: second byte (`(data1 & 0xFF00) >> 8`), where `0xA` is key-down and `0xB` is key-up.

Supported hardware key codes (matching `IOKit/hidsystem/ev_keymap.h`):

| Key | Integer Code | Logical HUD Class |
| --- | --- | --- |
| Sound Up | `0` | Volume |
| Sound Down | `1` | Volume |
| Brightness Up | `2` | Display Brightness |
| Brightness Down | `3` | Display Brightness |
| Sound Mute | `7` | Volume |
| Illumination Up | `21` | Keyboard Backlight |
| Illumination Down | `22` | Keyboard Backlight |

Step sizing rules:
- Standard press: `1 / 16` (`0.0625`, one hardware segment).
- Fine adjustment (`Option + Shift` held without Command): `1 / 64` (`0.015625`, quarter-segment).
- `Option` held without `Shift`: reserved for opening Settings panes (Sound for volume keys, Displays for brightness keys, Keyboard for illumination keys).

Only key-down transitions (`0xA`) produce state mutations or HUD triggers. Unrecognized codes or non-system events pass through unmodified.

---

## 2. Passive Observation vs. Suppressing Interception

There are two independent capabilities controlled by user preferences:

1. **Notch HUD Display (`showNotchOSD`)**:
   - Enables passive listeners (`VolumeManager`, `BrightnessManager`, `KeyboardBacklightManager`) to display HUD feedback inside the notch or island whenever hardware levels change.
   - **MUST NEVER** install or require an active swallowing `CGEvent` tap on its own. When `hideSystemOSD == false` and legacy `hudReplacement == false`, macOS continues to handle all hardware key presses natively and shows its built-in popup while passive observers mirror changes into the notch.

2. **System Popup Suppression (`hideSystemOSD` or legacy `hudReplacement`)**:
   - Installs an active `CGEvent.tapCreate` (`defaultTap` at `.cgSessionEventTap`) listening to `NX_SYSDEFINED` events so LiquidDynamo can handle the key press and suppress the native macOS HUD popup.
   - Requires Accessibility permission (`AXIsProcessTrusted()`). If Accessibility is unavailable, status surfaces cleanly as needing Accessibility and hardware keys are never dropped.

```
showNotchOSD == true, hideSystemOSD == false
   └─► Passive listeners only; event tap stopped; macOS handles all keys natively

hideSystemOSD == true (or legacy hudReplacement == true)
   └─► Start CGEvent tap (if AXIsProcessTrusted)
         ├─ Tap disabled by timeout/user input -> immediately re-enable
         └─ Key-down recognized for HUD class K:
               ├─ InterceptSafety[K] == backedOff -> return event (pass to macOS)
               └─ InterceptSafety[K] == active    -> apply verified write
                                                     ├─ changed || atRail -> record success, swallow event
                                                     └─ !changed && !atRail -> increment failures; once failures >= 2, back off K and pass event to macOS on future presses
```

---

## 3. Intercept Safety & Consecutive-Failure Backoff

Returning `nil` from an active `CGEvent` tap prevents macOS (`BezelServices` / `OSDUIHelper`) from seeing the key. If LiquidDynamo's own hardware write fails (for example on fixed-volume HDMI/DisplayPort audio devices, unsupported external displays without DDC/DisplayServices, or App Sandbox denials of private brightness APIs), unconditionally swallowing keys locks the user out of hardware control.

Per-class safety state (`volume`, `brightness`, `keyboardBacklight`):

- **Threshold**: `2` consecutive genuine failures transition that HUD class into `backedOff` (`isIntercepting == false`).
- **Rail hits are NOT failures**:
  - Increasing past `1.0` when already at `1.0`, or decreasing past `0.0` when already at `0.0` (including unmuted at zero / muted at zero as specified per action), succeeds with `atRail = true` and resets the failure counter to `0`.
- **Genuine failure**:
  - `changed == false` AND `atRail == false` (write rejected or API unavailable).
  - Failure #1: increments failure counter (`1`), allows 1 retry.
  - Failure #2+: marks that class backed off (`isIntercepting == false`), resets the class to pass-through mode for subsequent presses, and publishes the backed-off class set to UI settings.
- **Synchronous vs. Asynchronous writes**:
  - Synchronous drivers (CoreAudio volume, synchronous `DisplayServices`) evaluate `recordOutcome` immediately in the event callback path. On genuine failure #2 (or if API is known unavailable up front), pass the current or subsequent events through to macOS without locking the user out.
  - Asynchronous XPC drivers (`CoreBrightness` / XPC helper) record outcomes when the reply returns. If the channel is known unavailable before dispatch, pass the key event through to macOS immediately rather than optimistically swallowing it.
- **Automatic Recovery & Manual Reset**:
  - Default audio output device change clears `.volume` backoff and failure count.
  - Display configuration change (`NSApplication.didChangeScreenParametersNotification`) clears `.brightness` backoff and failure count and re-evaluates brightness availability.
  - Stopping, restarting, re-enabling the event tap, or tapping "Re-arm Key Interception" clears all class failure counts and backoff flags.

---

## 4. Hardware Control Truthfulness & Sandbox / Private API Disclosure

### Rule 6 Disclosures (Private Frameworks & Privileged APIs)
The hardware control pipeline touches non-public Apple interfaces and privileged input APIs that carry macOS upgrade breakage and App Store review risks:
1. **`CGEvent.tapCreate` (`NX_SYSDEFINED`)**: Public CoreGraphics API requiring Accessibility trust (`AXIsProcessTrusted`) and suppressed input-monitoring behavior. Cannot function inside an App Store sandbox without entitlement exceptions.
2. **`DisplayServices.framework` (`DisplayServicesGetBrightness`, `DisplayServicesSetBrightness`, `DisplayServicesCanChangeBrightness`)**: Private system framework loaded via `dlopen`. May fail silently or return `false` / non-zero status on external displays, headless nodes, or future macOS releases.
3. **`SkyLight.framework` (`IOAVServiceCreateWithService`, `IOAVServiceWriteI2C`, `IOAVServiceReadI2C`)**: Private DDC/CI channel for external monitors. Subject to App Sandbox restrictions and silicon/cable compatibility.
4. **`CoreBrightness.framework` (via XPC helper `DisplayBrightnessClient` / `KeyboardBrightnessClient`)**: Undocumented Objective-C classes accessed over XPC; unavailable in strict App Sandbox builds unless companion helper is installed and signed outside the sandbox.

### Hardware Rules
- **Audio Volume (`VolumeManager`)**:
  - Never run `NSAppleScript` inside CoreAudio's synchronous write path as a blind fallback when `!hasVolumeControl` or fixed-volume outputs exist.
  - Explicitly return `Bool` success from scalar writes and mute toggles, verify `AudioObjectSetPropertyData` status, and compute `(changed, atRail)` from pre-write and post-write hardware state.
  - Post an internal notification whenever the active default audio output device changes so `InterceptSafety` can re-arm `.volume`.
- **Display Brightness (`BrightnessManager`)**:
  - Reflect true hardware reachability in `isBrightnessAvailable` based on actual readable `DisplayServices` / verified XPC response rather than optimistic booleans.
  - Stop idle `0.8s` polling timers when `isBrightnessAvailable == false`; restart/re-probe cleanly when screen parameters change (`didChangeScreenParametersNotification`) or when `showNotchOSD` is toggled on.
- **Keyboard Backlight (`KeyboardBacklightManager`)**:
  - Expose availability honestly (`isKeyboardBacklightAvailable`) from actual XPC probe/write results; mark failure cleanly if XPC helper is unreachable or denied rather than fabricating backlight levels.

---

## 5. Segment, Glow & Label Formatting

All HUD views (closed sneak-peek / inline notch wing, expanded open-notch HUD, Dynamic Island alert) share pure formatting rules:

- **Input clamping**: normalize raw float level into `[0.0, 1.0]`.
- **Mute display**: when `muted == true`, label formats as `"Muted"` (or localized equivalent); otherwise rounded integer percentage `"0%"`–`"100%"`.
- **16-segment quantization**: `filledSegments(for: level, isMuted: muted, totalSegments: 16)` returns `0` when muted or `<= 0.001`, otherwise `Int((clamped * 16).rounded())` clamped to `[0, 16]`.
- **Warm/hot glow staging**:
  - Level `<= 0.80` (or muted): stage `0` (standard fill).
  - Level `> 0.80` and `<= 0.90`: stage `1` (warm orange highlight).
  - Level `> 0.90`: stage `2` (high crimson/amber peak highlight).
- **Non-controllable devices**:
  - Slider interaction in open-notch HUD is disabled cleanly when the target output/display lacks control (`!hasVolumeControl` or `!isBrightnessAvailable`) instead of accepting futile drags.
  - Open-notch header shows HUD for controllable internal OR external outputs/displays (`hasVolumeControl || hasExternalAudioDevice` for audio; `BrightnessManager.shared.isBrightnessAvailable || MultiDisplayBrightnessService.shared.hasExternalControllableDisplay` for brightness).
