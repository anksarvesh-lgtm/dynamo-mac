# Roadmap

**Done (v0.1):**
- Notch-anchored island with compact, minimal, expanded and search states
- Priority engine with deterministic ordering
- Liquid Glass
- Universal media (Music, Spotify, VLC, browsers)
- Timers, downloads, mic/camera, battery, devices, network, calendar and clipboard
- Settings, debug panel and performance overlay
- Search (apps, files, actions, web), AI research with citations, automation engine
- CI and releases

**Next**
- Automation rule editor UI (the engine and storage already exist)
- Drag and drop files onto the island (AirDrop/shelf)
- Per-app media allow list; more browsers
- Focus-mode-aware quiet hours
- Localization
- Optional Sparkle-style update check against GitHub Releases

**Known limits (platform)**
- macOS has no public API to read system-wide Now Playing. Island supports apps that expose their state publicly (see README).
- Calls (FaceTime and others) have no public observation API, so the `call` kind is available to custom and test activities only.
- Island can see that the mic or camera is in use, but not stop another app's recording.
