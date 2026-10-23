<!-- BRIEF: COMMIT=mtime-17 HASH=70903e71 DATE=2026-10-23T15:47:06.615Z -->
# Project Brief: LiquidDynamo-1.9.2
- **Commit**: `mtime-17` | **Updated**: 2026-10-23T15:47:06.615Z | **Files Tracked**: 412

## Overview
<h1 align="center">
  <br>
  LiquidDynamo
  <br>
</h1>

## Tech Stack
- Generic / Stack undetected

## Folder Layout (Top 2 Levels)
- `.`: 11 files
- `Configuration/dmg`: 4 files
- `docs/AIRPODS_FEASIBILITY.md`: 1 file
- `docs/CODEBASE_MAP.md`: 1 file
- `docs/DEVICE_SHOWCASE_PLAN.md`: 1 file
- `docs/DISTRIBUTION_GUIDE.md`: 1 file
- `docs/FIX_PLAN.md`: 1 file
- `docs/ISLAND_MOTION_SPEC.md`: 1 file
- `docs/LIQUID_ENGINE_PLAN.md`: 1 file
- `docs/MANUAL_TEST_CHECKLIST.md`: 1 file
- `docs/MOTION_AUDIT.md`: 1 file
- `docs/NOTCH_UI_PLAN.md`: 1 file
- `docs/REBRAND_AUDIT.md`: 1 file
- `liquiddinamo/.DS_Store`: 1 file
- `liquiddinamo/animations`: 2 files
- `liquiddinamo/Assets.xcassets`: 37 files
- `liquiddinamo/components`: 76 files
- `liquiddinamo/ContentView.swift`: 1 file
- `liquiddinamo/enums`: 1 file
- `liquiddinamo/extensions`: 13 files
- `liquiddinamo/Features`: 124 files
- `liquiddinamo/helpers`: 7 files
- `liquiddinamo/Info.plist`: 1 file
- `liquiddinamo/liquid.m4a`: 1 file
- `liquiddinamo/LiquidDynamo.entitlements`: 1 file
- `liquiddinamo/LiquidDynamoApp.swift`: 1 file
- `liquiddinamo/LiquidViewCoordinator.swift`: 1 file
- `liquiddinamo/Localizable.xcstrings`: 1 file
- `liquiddinamo/managers`: 10 files
- `liquiddinamo/MediaControllers`: 8 files
- `liquiddinamo/menu`: 1 file
- `liquiddinamo/metal`: 2 files
- `liquiddinamo/models`: 8 files
- `liquiddinamo/observers`: 3 files
- `liquiddinamo/Preview Content`: 1 file
- `liquiddinamo/private`: 1 file
- `liquiddinamo/Providers`: 1 file
- `liquiddinamo/Resources`: 46 files
- `liquiddinamo/Shortcuts`: 1 file
- `liquiddinamo/sizing`: 2 files

## Likely Entry Points
- `LiquidDynamoXPCHelper/main.swift`

## Key Commands
- No build/test scripts found

## Project Rules (RULES.md)
# LiquidDynamo — Engineering & Contribution Rules

This document outlines the core engineering guidelines, design constraints, and rules of engagement for developing, maintaining, and contributing to **LiquidDynamo**.

---

## 1. Architectural Principles

1. **Native macOS Synergy**:
   - LiquidDynamo is built natively for macOS using **SwiftUI**, **AppKit**, **CoreAudio**, **Metal**, and **SceneKit**.
   - Do NOT introduce bulky cross-platform frameworks, Electron layers, or unnecessary third-party dependencies.

2. **Preserve Established Visual Identity**:
   - Liquid Glass shaders, fluid morphing shapes, organic spring physics (`IslandMotion.shared`), and dark OLED blending are core hallmarks of the application.
   - Never replace the fluid glass/droplet aesthetic with generic, blocky rectangular views or flat UI templates.

3. **Multi-Display & Hardware Notch Support**:
   - Always rely on `NotchSafeAreaEngine.shared` to read physical screen safe areas, auxiliary top areas, and har
