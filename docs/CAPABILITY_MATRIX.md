# LiquidDynamo — Production Capabilities Matrix & Architecture Audit (Phase 1)

This matrix defines the technical categorization and API boundary for all features in LiquidDynamo, strictly adhering to public macOS interfaces, technical honesty, and permission boundaries.

## 1. Feature Classification Matrix

| Feature | Category | Public macOS API / Framework | Permission Required | Availability & Handling Policy |
| :--- | :--- | :--- | :--- | :--- |
| **Persistent Notch Overlay Window** | **Native** | AppKit (`NSWindow`, `NSWindow.Level.floating`, `NSScreen.auxiliaryTopLeftArea`) | None | Fixed overlay across notch/wings/expansion area. Unused areas transparent to mouse clicks. |
| **Power & MagSafe Telemetry** | **Native** | IOKit.ps (`IOPSCopyExternalPowerAdapterDetails`, `IOPSCopyPowerSourcesInfo`) | None | Real adapter name, live charging state, battery percentage, real wattage when measured. No dummy 32W fallback. |
| **System Thermal Status** | **Native** | Foundation (`ProcessInfo.processInfo.thermalState`) | None | Categorical status (`nominal`, `fair`, `serious`, `critical`). No private SMC keys or fabricated fan RPM. |
| **System CPU & Memory Metrics** | **Native** | Darwin/mach (`host_statistics64`, `host_cpu_load_info`) | None | Real system CPU load % and memory pressure. Throttled sampling. |
| **Network Throughput** | **Native** | Darwin (`getifaddrs`, `if_data`) | None | Live network interface TX/RX byte counter deltas. |
| **LiquidDynamo Notifications** | **Native** | UserNotifications (`UNUserNotificationCenter`) | Notifications | Application-owned notification alerts with rich banners and sound cues. |
| **Liquid Glass Shaders & SDF** | **Custom** | SwiftUI Material, Metal Shading Language (`LiquidIslandShader.metal`) | None | Smoked charcoal glass (`#17191C`), directional glare convergence, G2 superellipse, Fresnel reflection. |
| **Adaptive 3-Slide Carousel** | **Custom** | SwiftUI View hierarchy | None | Slide 1 (Productivity), Slide 2 (System Tools), Slide 3 (Watcher). Dynamic Slide 0 for active media. |
| **In-Place Detail Expansion** | **Custom** | SwiftUI GeometryReader & spring physics | None | In-place ~2x compact height expansion inside central island; flanking wings remain anchored. |
| **Screen Color Eyedropper** | **Permission-Dependent** | CoreGraphics / ScreenCaptureKit (`CGWindowListCreateImage`, `CGPreflightScreenCaptureAccess`) | Screen Recording | Explicitly requests permission; shows informative unavailable state if denied without crashing. |
| **External Media Automation** | **Permission-Dependent** | AppleScript / ScriptingBridge (`NSAppleScript`, System Events) | Automation (Music/Spotify) | Only prompts for approved players; verifies active playback before promoting media slide. |
| **Clipboard History** | **Permission-Dependent** | AppKit (`NSPasteboard.general`) | Accessibility (optional) | Local tracking of copied text, links, and images. Zero network transmission. |
| **Bluetooth Audio Accessories** | **Integration-Dependent** | CoreAudio (`AudioObjectGetPropertyData`), CoreBluetooth | Bluetooth | Discovers active audio output devices and reads GATT battery service when supported. |
| **Phone Bridge Local Transfer** | **Integration-Dependent** | Network / Local USB Daemon | Local Network | Secure local socket pairing with companion mobile client. |
| **Global Notification Center Scraping** | **Unavailable** | None (Private SQLite / UI Scraping prohibited) | N/A | Apple provides no public API to intercept other apps' notifications. Never fabricated. |
| **Hardware SMC Fan/Temp Keys** | **Unavailable** | None (Private AppleSMC prohibited) | N/A | Strictly prohibited. Handled transparently via `ProcessInfo.thermalState`. |
| **Global Mic/Camera Snooping** | **Unavailable** | None (TCC private states prohibited) | N/A | Only LiquidDynamo's own AVFoundation/ScreenCaptureKit sessions are tracked and indicated. |

---

## 2. Capability Registry Verification
Implemented programmatically in [`liquiddinamo/Features/Common/CapabilityRegistry.swift`](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/Features/Common/CapabilityRegistry.swift).
Any feature not supported or lacking user authorization presents an informative, styled empty/unavailable state rather than crashing or displaying fabricated mock data.
