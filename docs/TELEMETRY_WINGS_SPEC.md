# Behavioral Specification: Clean-Room Telemetry Wings, 5-Zone Thermal Scale & External Floating Pill

## Purpose

Provide configurable left and right notch wings (and symmetrical floating side pills flanking a centered island capsule on external / non-notched displays) showing truthful hardware and OS telemetry across ten telemetry metrics without numerical jitter, text clipping, fabricated sensor readings, or private-framework crashes under App Sandbox.

---

## 1. Five-Zone Thermal Classification & Gradient Scale

### Zone Definitions & Default Thresholds

Temperatures (in degrees Celsius) are partitioned into five strictly ascending zones:

| Zone | Semantic State | Default Condition | Display Color |
| :--- | :--- | :--- | :--- |
| Cool | Low thermal load | `T <= 45.0 °C` | Cyan (`#26D1DB`) |
| Normal | Typical operating load | `45.0 < T <= 60.0 °C` | Green (`#38D661`) |
| Elevated | Sustained load | `60.0 < T <= 75.0 °C` | Yellow (`#F5D12E`) |
| High | Heavy thermal load | `75.0 < T <= 88.0 °C` | Orange (`#FF801F`) |
| Critical | Thermal throttling risk | `T > 88.0 °C` | Red (`#F23333`) |

### Threshold Sanitization Rules

User-configurable thresholds `(coolMax, normalMax, elevatedMax, highMax)` must always maintain strict ordering `coolMax < normalMax < elevatedMax < highMax`:

- Clamp `coolMax` into `[20.0, 90.0]`.
- Ensure `normalMax >= coolMax + 2.0`.
- Ensure `elevatedMax >= normalMax + 2.0`.
- Ensure `highMax >= elevatedMax + 2.0`.

### Continuous Gradient Mapping & Fallback Truthfulness

```
  T <= coolMax ──> pure Cyan
  (coolMax .. normalMax]   ──> Cyan  --> Green
  (normalMax .. elevatedMax] ──> Green --> Yellow
  (elevatedMax .. highMax] ──> Yellow --> Orange
  (highMax .. highMax+10]  ──> Orange --> Red
  T >= highMax + 10        ──> pure Red
```

- When hardware temperature cannot be read (e.g., disabled, unsupported, or denied under App Sandbox), temperature displays `"—"` and normalized severity falls back exclusively to `ProcessInfo.thermalState`:
  - `.nominal` -> Normal (Green)
  - `.fair` -> Elevated (Yellow)
  - `.serious` -> High (Orange)
  - `.critical` -> Critical (Red)
- A numeric degree value is **never** synthesized when hardware telemetry is absent.

---

## 2. Ten Telemetry Metrics & Data Truthfulness

1. **CPU Usage (%)**: differential `host_processor_info` across active logical cores, formatted as integer percentage (`0%–100%`).
2. **CPU Temperature (°C)**: Apple Silicon `IOHID` thermal die average when opt-in probe succeeds; otherwise `nil` rendered as `"—"`.
3. **RAM Usage (%)**: `(active + wired + compressed) / physicalMemory`, `0%–100%`.
4. **Memory Pressure**: combines VM pressure signal (`sysctlbyname("kern.memorystatus_vm_pressure_level")` when non-zero: level `1` normal, `2` warning -> minimum `0.65`, `4` critical -> minimum `0.90`) with active/wired/compressed utilization ratio, classified as `Normal` (`< 0.60`), `Elevated` (`0.60 ..< 0.85`), or `Critical` (`>= 0.85`).
5. **Network Download Speed**: non-loopback, non-tunnel physical interface inbound byte deltas via `getifaddrs`.
6. **Network Upload Speed**: non-loopback, non-tunnel physical interface outbound byte deltas via `getifaddrs`.
7. **System Battery (%)**: reads `IOPSCopyPowerSourcesInfo` / `IOPSCopyPowerSourcesList`. When no battery power source exists (desktop Macs), reports battery unavailable (`hasBattery = false`) and renders `"—"` instead of `100%`.
8. **Bluetooth Accessory Battery (%)**: reads connected accessory battery percentage; renders `"—"` if no accessory battery is reported.
9. **System Volume (%)**: reads CoreAudio default output scalar volume and mute state.
10. **Display Brightness (%)**: reads current display brightness; renders `"—"` when unavailable on external monitors without software brightness control.

*(Additional wing slots such as Clock, Weather, Media, Keep Awake remain preserved.)*

---

## 3. Anti-Jitter Formatting, Hover Inspection & Click-to-Expand Details

```
  [Idle / Collapsed Wing]
         |
         +--> Hover enter --------------------+
         |                                    v
         |                          [Detail Breakdown Shown]
         +--> Click / Tap ------------------->  (starts 3.0s auto-collapse timer;
                                                 toggling or clicking outside cancels/resets)
```

- **Monospaced Numerals & Width Stabilization**:
  - Wing value labels use fixed/tabular numerals (`monospacedDigit`) and single-line non-wrapping layout.
  - Auto-fit width measurements snap up to `8 pt` buckets and require at least `4 pt` change (or a transition into/out of detail expansion) before updating target wing width, preventing 1-pixel digit updates (`9% -> 10%`) from triggering window-frame spring animations.
  - Wing width is clamped cleanly between `[38 pt, safeMaxWingWidth]`, where `safeMaxWingWidth` preserves headroom inside the unobstructed auxiliary menu-bar region (or half remaining non-notched screen width).
- **Detail Breakdown**:
  - Normal collapsed state shows primary icon + compact value (`24%`, `62%`, `↓1.2M`).
  - Hovering or clicking to expand reveals crisp contextual detail without changing notch height (`24% · 54°C` or `Fair`, `62% · Normal`, `↓1.2M ↑240K`, `88% · 2h 10m`, BT device short name + `%`), collapsing automatically after `3.0 s` when activated by click.

---

## 4. Symmetrical External-Display Dynamic Island Experience

```
  Non-notched / External Display:
  [ Left Floating Wing ] <- 8pt -> ( Central Floating Capsule 160pt ) <- 8pt -> [ Right Floating Wing ]
     trailing inside maxW             fixed height == closedHeight             leading inside maxW
```

- On displays without a physical hardware notch (`notchRect == .zero`):
  - Left and right floating wing pills match the exact height and continuous capsule curvature of the central floating island pill.
  - Both side slots reserve matching horizontal container width (`maxW = max(leftWidth, rightWidth)`) so the central pill remains centered on the display horizontally even when only one wing is enabled or side metrics have unequal text lengths.
  - `wingsBuiltInDisplayOnly` hides wings on external/non-built-in displays when enabled, and fullscreen hiding respects both per-display `FullscreenMediaDetector` state and `hideWingsInFullScreen`.

---

## 5. Edge Cases

- **No hardware battery (Mac Studio / Mac mini / iMac)**: `hasBattery == false`, displays `"—"` rather than `100%`.
- **Unsanitized / inverted threshold preferences**: `ThermalThresholds.sanitized()` repairs ordering cleanly before interpolation.
- **Thermal probe unavailable inside sandbox**: returns `nil` cleanly on first failure without spinning retries; thermal tint tracks `ProcessInfo.thermalState`.
- **Very narrow external or scaled displays**: `safeMaxWingWidth` caps expansion before overlapping screen edges or status items.
