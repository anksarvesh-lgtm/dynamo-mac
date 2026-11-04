# LiquidDynamo — Architecture & Component Map

## Overview
LiquidDynamo is a native macOS application that creates a fluid, organic Dynamic Island experience around the physical hardware notch and on external displays.

```mermaid
flowchart TD
    subgraph UI Presentation
        ContentView --> LiquidOrganicNotchView
        ContentView --> LiquidProductivityDashboardView
        ContentView --> LiquidGlassSystem
    end

    subgraph Window & Display Layer
        LiquidDynamoWindow
        LiquidDynamoSkyLightWindow
        NotchSafeAreaEngine
    end

    subgraph Coordinators & Observers
        LiquidViewCoordinator
        IslandController
        MediaKeyInterceptor
        NowPlayingController
    end

    subgraph Service Engines
        SystemStatsService
        NetworkThroughputService
        PowerloadDownloadEngine
        PhoneBridgeEngine
        ClipboardHistoryService
        DeviceMonitor
    end

    UI Presentation --> Coordinators & Observers
    Coordinators & Observers --> Service Engines
    Coordinators & Observers --> Window & Display Layer
```

## Key Modules & Locations

| Component | Path | Responsibility |
| :--- | :--- | :--- |
| **Window Host** | `liquiddinamo/components/Notch/LiquidDynamoWindow.swift` | Primary transparent `NSPanel` hosting SwiftUI Dynamic Island. |
| **SkyLight Window** | `liquiddinamo/components/Notch/LiquidDynamoSkyLightWindow.swift` | Window utilizing SkyLight private APIs for notch blending. |
| **Safe Area Engine** | `liquiddinamo/helpers/NotchSafeAreaEngine.swift` | Hardware notch measurements, screen geometry, wing width calculations. |
| **Island Controller** | `liquiddinamo/Features/Motion/IslandController.swift` | State machine governing `.compact`, `.expanded`, `.minimal` states. |
| **View Coordinator** | `liquiddinamo/LiquidViewCoordinator.swift` | Orchestration between active tabs, alerts, and sneak-peek HUD. |
| **Media Key Interceptor** | `liquiddinamo/observers/MediaKeyInterceptor.swift` | CGEvent tap intercepting volume/brightness hardware keystrokes. |
| **Now Playing** | `liquiddinamo/MediaControllers/NowPlayingController.swift` | MediaRemote adapter subprocess management and playback telemetry. |
| **Liquid Glass System** | `liquiddinamo/Features/Dashboard/LiquidGlassSystem.swift` | Material shaders, optical refraction, specular highlights, and chromatic rims. |
| **Productivity Dashboard** | `liquiddinamo/Features/Dashboard/LiquidProductivityDashboardView.swift` | System telemetry, quick apps, 3D device models, dropper shelf. |
| **Powerload Engine** | `liquiddinamo/Features/Powerload/` | Multi-stream network bonding and download acceleration. |
| **Phone Bridge** | `liquiddinamo/Features/PhoneBridge/` | Android/iOS wireless connectivity, notifications, and file transfer. |
| **Clipboard History** | `liquiddinamo/Features/Clipboard/` | Encrypted, privacy-first local clipboard ring buffer. |

