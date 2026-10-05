import { CodeModuleInfo, SpecDoc } from '../types/liquiddynamo';

export const SPEC_DOCS: SpecDoc[] = [
  {
    id: 'island-motion',
    title: 'Dynamic Island Motion Specification',
    subtitle: 'Apple Dynamic Island Physics & 5-State Machine',
    date: 'October 2026',
    tags: ['Physics', 'SwiftUI', 'Animation', 'States'],
    filePath: 'LiquidDynamo/docs/ISLAND_MOTION_SPEC.md',
    summary: 'Defines the 5 island states (Idle, Compact, Minimal, Expanded, Alert Pop), legal transitions, continuous squircles, and phase-staggered choreography.',
    content: `# LiquidDynamo Dynamic Island Motion Specification

### 1. Design Philosophy & Motion Principles
The iPhone Dynamic Island feels alive because it never behaves like a static, rectangular window. It behaves like an **elastic, fluid physical silicone element** integrated directly into the hardware cutout.

**Core Tenets:**
1. **Never Cut, Always Morph**: The black container must smoothly deform from one shape to the next. It never pops or snaps into place.
2. **Staggered Content Choreography**: Content inside the island must not scale with the container. Old content leaves first with a quick blur-out; the container moves; new content enters with an elastic blur-in.
3. **No Uncoordinated Timers**: Hover sequencing, auto-dismiss, and state switches are unified under a single state machine.
4. **Continuous Curvature**: All rounded corners use Apple continuous curvature (squircles), scaling proportionally with container height.

### 2. The 5 Island States
- **1. Idle**: Exactly matches hardware notch bounds (~185 × 32 pt). Completely inert and zero CPU overhead.
- **2. Compact**: The notch stretches horizontally at native notch height (32 pt), revealing symmetric or asymmetric "wings" (e.g. album art + audio waveform).
- **3. Minimal (Multi-Activity)**: Used when 2 distinct activities run concurrently. Primary stays in compact notch; secondary detaches as a 28×28 pt floating satellite bubble separated by an 8 pt gap.
- **4. Expanded**: Full interactive dashboard (~640 × 190 pt). Houses media controls, AirPods 3D space, quick drop shelf, and calendar.
- **5. Alert Pop**: Transient high-priority announcements (~380–420 × 44 pt) with energetic overshoot spring and 3–4 second dwell timer.

### 3. Spring Physics Parameters
- **expandSpring**: \`Animation.spring(response: 0.45, dampingFraction: 0.75)\` — weighted, expansive momentum.
- **collapseSpring**: \`Animation.spring(response: 0.36, dampingFraction: 0.86)\` — snappy, critically damped retraction with zero oscillation.
- **alertPopSpring**: \`Animation.spring(response: 0.40, dampingFraction: 0.65)\` — bouncy overshoot for peripheral alerts.`
  },
  {
    id: 'liquid-engine',
    title: 'Master Plan: Liquid Island Engine (v2.0)',
    subtitle: 'Signed-Distance Field (SDF) & 8-Lobe Metal Shaders',
    date: 'October 2026',
    tags: ['Metal', 'SDF', 'Math', 'Architecture'],
    filePath: 'LiquidDynamo/docs/LIQUID_ENGINE_PLAN.md',
    summary: 'Architectural blueprint replacing rigid capsule clips with organic 3D signed-distance fields, polynomial smooth minimum (smin), and an 8-lobe liquid geometry.',
    content: `# Master Plan: Liquid Island Engine (v2.0)

### 1. Invariants & Acceptance Rules
- **Rule 1 (Notch is a Hole)**: Nothing is ever drawn inside \`notchRect\` except the pure optical black fill (\`#000000\`). No icons or text ever clip into the camera cutout.
- **Rule 2 (Slot Segregation)**: Top band content exists exclusively in \`leftSlot\` (\`x < notchRect.minX\`) or \`rightSlot\` (\`x > notchRect.maxX\`).
- **Rule 3 (Auto-Sizing)**: SwiftUI \`PreferenceKey\` measurement pipeline reads intrinsic content size; continuous springs drive continuous lobe dimensions.
- **Rule 4 (Autonomous Dwell)**: Timed activities dwell for \`(2.5s + 0.04s * charCount)\` clamped to 8.0s; cursor hover suspends timer.
- **Rule 5 (Zero-Cost Idle)**: At idle, Metal shaders deallocate, CADisplayLink pauses, and \`window.ignoresMouseEvents = true\`. CPU usage is near 0.0%.

### 2. 8-Lobe Geometric Model & Polynomial smin
The liquid shape is represented as a union of 8 distinct lobes:
- Lobe 0: Root (lip below physical notch)
- Lobe 1: Body (primary content capsule)
- Lobe 2 & 3: Wing Left & Wing Right (status indicators)
- Lobe 4: Droplet (viscous gooey neck between root and body)
- Lobe 5 & 6: Satellite 1 & 2 (detached bubbles)
- Lobe 7: Auxiliary particle splash

Lobes are merged via polynomial smooth minimum:
\`\`\`math
smin(d1, d2, k) = min(d1, d2) - max(k - |d1 - d2|, 0)^2 / (4 * k)
\`\`\`
Smoothing parameter \`k\` dynamically expands to 28–36 pt during birth/swell, and tightens to 8–12 pt when settled.`
  },
  {
    id: 'airpods-feasibility',
    title: 'AirPods Integration Feasibility Spike',
    subtitle: 'Apple Accessory Protocol (AAP) & CoreBluetooth',
    date: 'October 2026',
    tags: ['AirPods', 'Bluetooth', 'CoreMotion', 'Hardware'],
    filePath: 'LiquidDynamo/docs/AIRPODS_FEASIBILITY.md',
    summary: 'Technical feasibility spike for AirPods 1st/2nd Gen, AirPods Pro, and Max integration using CoreBluetooth, IORegistry, and CMHeadphoneMotionManager.',
    content: `# AirPods Integration Feasibility Spike Report

### Target System & Supported Models
- **Target OS**: macOS 14.0+ (Sonoma, Sequoia) on Apple Silicon & Intel
- **Supported Hardware**: AirPods 1st/2nd Gen, AirPods 3/4, AirPods Pro 1/2, AirPods Max.

### Architecture & Protocol Findings
1. **Battery & Case Lid Tracking**:
   - Reads battery levels (Left, Right, Case) via \`IOBluetoothDevice\` and CoreBluetooth peripheral service broadcasts.
   - Dual orbit arcs render real-time charge with threshold warnings at 15% and 5%.
2. **Noise Control Mode Switching**:
   - Communicates with Bluetooth Audio HAL plugin to switch between:
     - Active Noise Cancellation (ANC)
     - Transparency Mode
     - Adaptive Audio
     - Off
3. **Head Tracking Mirror**:
   - Integrates with \`CMHeadphoneMotionManager\` to mirror head yaw, pitch, and roll in real-time onto a 3D rendered AirPods model in SceneKit.`
  },
  {
    id: 'device-showcase',
    title: '3D Device Showcase Architecture Plan',
    subtitle: 'SceneKit Rendering Pipeline & Peripheral Cache',
    date: 'October 2026',
    tags: ['SceneKit', '3D', 'Cache', 'Peripherals'],
    filePath: 'LiquidDynamo/docs/DEVICE_SHOWCASE_PLAN.md',
    summary: 'Zero-latency peripheral detection with SceneKit 3D device rendering, cosmic starfield backdrop, and memory-safe caching hierarchy.',
    content: `# Boring Notch / LiquidDynamo 3D Device Showcase Plan

### Overview
When external hardware connects to the Mac (AirPods, Magic Mouse, Magic Keyboard, DualSense controllers, Beats headphones):
1. Peripheral identity resolver determines vendor ID & product ID.
2. SceneKit asynchronously hydrates low-poly PBR 3D model with subtle ambient lighting.
3. Orbit battery indicators wrap around the hardware model with dynamic state color coding.

### Performance & Energy Budget
- Renders only when expanded or in Alert Pop mode; terminates rendering loop when collapsed.
- Max 60 FPS capped with dynamic frame throttling during battery saver mode.
- Geometry memory footprint bounded below 15 MB.`
  },
  {
    id: 'rebrand-audit',
    title: 'Rebrand Audit & Migration Plan',
    subtitle: 'From Boring Notch to LiquidDynamo (Agrigence)',
    date: 'October 2026',
    tags: ['Legal', 'GPL-3.0', 'Agrigence', 'Audit'],
    filePath: 'LiquidDynamo/docs/REBRAND_AUDIT.md',
    summary: 'Phase 1 audit detailing bundle ID updates, GPL-3.0 upstream attribution compliance, Sparkle updater migration, and clean architectural refactoring.',
    content: `# LiquidDynamo Rebrand Audit & Migration Plan

### Brand & Legal Guardrails
- **Target Brand**: LiquidDynamo
- **Developer / Organization**: Agrigence
- **License**: GNU General Public License v3.0 (GPL-3.0)
- **Main App Bundle ID**: \`com.agrigence.liquiddynamo\`
- **Helper Bundle ID**: \`com.agrigence.liquiddynamo.BoringNotchXPCHelper\`

### Architectural Modernizations
- Decoupled scattered \`Task.sleep\` routines into centralized \`IslandMotion.shared\` coordinator.
- Replaced hard-clipped rectangular frames with Apple continuous curvature squircles.
- Added custom native DMG packaging pipeline with \`dmgbuild\` and background artwork.`
  },
  {
    id: 'codebase-map',
    title: 'Codebase Architecture Map',
    subtitle: 'System Subsystems, Schemes & Windowing Model',
    date: 'October 2026',
    tags: ['Architecture', 'Windowing', 'XPC', 'AppKit'],
    filePath: 'LiquidDynamo/docs/CODEBASE_MAP.md',
    summary: 'Full directory walkthrough of the Xcode project, window layering over the macOS menu bar, XPC communication, and media player adapters.',
    content: `# LiquidDynamo Codebase Map & Subsystem Guide

### Window Layering & Event Passthrough
LiquidDynamo sits at \`NSWindow.Level.statusBar + 1\` or \`mainMenu + 1\` to overlay seamlessly over both the physical notch cutout and the macOS menu bar.
- Uses \`window.ignoresMouseEvents = true\` during idle to allow clicks to pass through to apps underneath.
- Activates interactive hit-testing strictly when cursor enters notch proximity or dynamic wings are active.`
  }
];

export const CODE_MODULES: CodeModuleInfo[] = [
  {
    id: 'features-airpods',
    name: 'AirPods 3D Space & AAP',
    path: '/LiquidDynamo/liquiddinamo/Features/AirPods',
    category: 'features',
    description: 'Implements zero-gravity 3D rendered AirPods models, orbit battery arcs, ANC mode switching (Noise Cancellation, Transparency, Adaptive, Off), and CoreMotion head tracking.',
    files: [
      'AirPodsContainerView.swift',
      'AirPodsMotionManager.swift',
      'AirPodsBatteryArcView.swift',
      'NoiseControlSelector.swift',
      'CosmicStarfieldView.swift'
    ],
    architecturalRole: 'Provides high-fidelity peripheral interaction when AirPods are in-ear or case lid opens.',
    invariants: [
      'Must read charge level without spawning auxiliary background processes',
      'Head tracking must gracefully fall back to inert model if CMHeadphoneMotionManager is unavailable'
    ],
    swiftSnippet: `// AirPods 3D Space Mode Handler
class AirPodsSpaceCoordinator: ObservableObject {
    @Published var leftBattery: Double = 0.85
    @Published var rightBattery: Double = 0.85
    @Published var caseBattery: Double = 0.94
    @Published var noiseMode: NoiseControlMode = .anc
    @Published var headHeading: simd_float3 = .zero
    
    func switchNoiseMode(_ mode: NoiseControlMode) {
        self.noiseMode = mode
        BluetoothAudioHelper.setListeningMode(mode.audioHalValue)
    }
}`
  },
  {
    id: 'features-motion',
    name: 'Liquid Island Motion Engine',
    path: '/LiquidDynamo/liquiddinamo/Features/Motion',
    category: 'rendering',
    description: 'State machine governing the 5 Dynamic Island states, tuned spring curves, and the 3-phase staggered content pipeline.',
    files: [
      'IslandMotion.swift',
      'IslandState.swift',
      'ContinuousSquircle.swift',
      'ContentChoreographer.swift',
      'DwellScheduler.swift'
    ],
    architecturalRole: 'Prevents animation jank by coordinating container deformation and internal content fade/blur transitions.',
    invariants: [
      'Content must blur-out BEFORE container morphs',
      'New content reveals ONLY after container reaches 60% of destination size',
      'Container must never snap or cut abruptly'
    ],
    swiftSnippet: `struct IslandSprings {
    static let expand = Animation.spring(response: 0.45, dampingFraction: 0.75)
    static let collapse = Animation.spring(response: 0.36, dampingFraction: 0.86)
    static let alertPop = Animation.spring(response: 0.40, dampingFraction: 0.65)
    
    static let contentOut = Animation.easeOut(duration: 0.15)
    static let contentIn = Animation.easeOut(duration: 0.28).delay(0.09)
}`
  },
  {
    id: 'features-hud',
    name: 'System HUD Replacements',
    path: '/LiquidDynamo/liquiddinamo/Features/VolumeControl',
    category: 'features',
    description: 'Replaces the bulky default macOS volume, brightness, and keyboard backlight HUD overlays with sleek, notch-integrated spring alerts.',
    files: [
      'VolumeHUDView.swift',
      'BrightnessHUDView.swift',
      'KeyboardBacklightHUDView.swift',
      'HUDListener.swift'
    ],
    architecturalRole: 'Listens to CoreAudio and IOKit hardware notification events to display unobtrusive top-center meters.',
    invariants: [
      'Zero display lag (<16ms) between keypress and meter render',
      'Auto-dismiss with 2.0s dwell timer with reset on repeated taps'
    ],
    swiftSnippet: `func handleVolumeChange(level: Float, isMuted: Bool) {
    IslandCoordinator.shared.presentAlert(
        .volume(level: level, isMuted: isMuted),
        dwellTime: 2.0
    )
}`
  },
  {
    id: 'features-shelf',
    name: 'Liquid Shelf & AirDrop',
    path: '/LiquidDynamo/liquiddinamo/components/Shelf',
    category: 'features',
    description: 'Quick-drop staging shelf positioned at the top of the display for holding files, images, and snippets, with one-click AirDrop trigger.',
    files: [
      'ShelfDropZone.swift',
      'ShelfItemView.swift',
      'AirDropService.swift',
      'FileStagingManager.swift'
    ],
    architecturalRole: 'Provides temporary friction-free staging area accessible from any desktop or fullscreen space.',
    invariants: [
      'Supports dragging multiple URLs, images, and text items',
      'Cleans up staged temp files when dismissed or sent'
    ],
    swiftSnippet: `struct ShelfDropZone: View {
    @Binding var stagedFiles: [URL]
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(stagedFiles, id: \\.self) { url in
                ShelfThumbnail(url: url)
            }
            AirDropButton(urls: stagedFiles)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }
}`
  },
  {
    id: 'metal-sdf',
    name: 'Metal SDF Liquid Shaders',
    path: '/LiquidDynamo/liquiddinamo/metal',
    category: 'rendering',
    description: 'Custom Metal compute & fragment shaders calculating 8-lobe 2D Signed Distance Fields with polynomial smooth minimum and 3D specular lighting.',
    files: [
      'LiquidShaders.metal',
      'MetalRenderer.swift',
      'LobeUniforms.h',
      'GooeyFilter.swift'
    ],
    architecturalRole: 'Creates organic fluid necking and liquid droplet emergence from the hardware notch.',
    invariants: [
      'Suspends CADisplayLink and deallocates pipeline when in Idle state',
      'Strictly leaves notchRect pure optical black'
    ],
    swiftSnippet: `// Metal SDF Polynomial smin
float smin(float d1, float d2, float k) {
    float h = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
    return mix(d2, d1, h) - k * h * (1.0 - h);
}`
  },
  {
    id: 'config-dmg',
    name: 'DMG Packaging & Automation',
    path: '/LiquidDynamo/Configuration/dmg',
    category: 'system',
    description: 'Self-contained Python dmgbuild script, TIFF background rendering, and bash automation for building signed, branded macOS DMGs.',
    files: [
      'create_dmg.sh',
      'dmgbuild_settings.py',
      'requirements.txt',
      'background.tiff'
    ],
    architecturalRole: 'Automates release packaging with icon positions: LiquidDynamo.app at (150, 180) and /Applications at (510, 180).',
    invariants: [
      'Validates .app existence before invocation',
      'Includes pinned hashes for dmgbuild dependencies in requirements.txt'
    ],
    swiftSnippet: `# Shell DMG packaging wrapper
bash build_dmg.sh
# Invokes dmgbuild -s Configuration/dmg/dmgbuild_settings.py "LiquidDynamo" "LiquidDynamo.dmg"`
  }
];

export const SYSTEM_REQUIREMENTS = {
  os: 'macOS 14.0 (Sonoma) or macOS 15.0+ (Sequoia)',
  architectures: 'Apple Silicon (M1 / M2 / M3 / M4) and Intel 64-bit Core i5/i7/i9',
  displays: 'MacBook Pro / Air with physical notch, external 4K/5K displays, Studio Display, iMac, Mac mini, Mac Studio',
  license: 'GNU General Public License v3.0 (GPL-3.0)',
  developer: 'Agrigence',
  upstream: 'Boring Notch (by TheBoredTeam)',
  version: 'v2.8-rc.1 / v1.4.0 Release'
};
