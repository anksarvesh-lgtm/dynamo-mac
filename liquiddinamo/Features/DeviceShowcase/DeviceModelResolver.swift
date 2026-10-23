//
//  DeviceModelResolver.swift
//  boringNotch
//
//  Created for Boring Notch
//

import AppKit
import Foundation
import SceneKit

// MARK: - Resolved Model Source

public enum ResolvedModelSource: Equatable {
    case cached(URL)
    case categoryUSDZ(URL)
    case storageFlatCard
    case proceduralStandIn(DeviceKind)

    public var isFile: Bool {
        switch self {
        case .cached, .categoryUSDZ: return true
        default: return false
        }
    }
}

// MARK: - Resolved Device Model

public struct ResolvedDeviceModel {
    public let scene: SCNScene
    public let sourceURL: URL?
    public let source: ResolvedModelSource
    public let tier: ModelSourceTier

    public init(
        scene: SCNScene,
        sourceURL: URL? = nil,
        source: ResolvedModelSource,
        tier: ModelSourceTier
    ) {
        self.scene = scene
        self.sourceURL = sourceURL
        self.source = source
        self.tier = tier
    }
}

// MARK: - Device Model Resolver

/// Resolves the optimal 3D model for any detected device.
/// Resolution hierarchy:
/// 1. Cached exact model for this device key under Application Support (~/Library/Application Support/.../DeviceModels/<deviceKey>/model.usdz)
/// 2. Category bundled USDZ at Resources/Models/Categories/<kind>.usdz
/// 3. Stand-in fallback:
///    - For storage devices: flat card with the system icon from NSWorkspace
///    - For other devices: stylized procedural SceneKit primitive model
@MainActor
public final class DeviceModelResolver {
    public static let shared = DeviceModelResolver()

    private let sceneCache = NSCache<NSString, SCNScene>()

    public init() {
        sceneCache.countLimit = 30
    }

    // MARK: - Public Resolution API

    /// Resolves the model for a device following the exact 3-step pipeline.
    public func resolveModel(for device: DeviceIdentity) async -> ResolvedDeviceModel {
        let cacheKey = NSString(string: device.stableKey)

        // Check in-memory scene cache first
        if let cachedScene = sceneCache.object(forKey: cacheKey) {
            return ResolvedDeviceModel(
                scene: cachedScene,
                sourceURL: nil,
                source: .cached(URL(fileURLWithPath: device.stableKey)),
                tier: .cached
            )
        }

        // 1. Tier 1: Check persistent DeviceModelStore for exact cached model
        if let storeURL = await DeviceModelStore.shared.getModelURL(for: device.stableKey),
           let scene = try? SCNScene(url: storeURL, options: nil) {
            Self.postProcessUSDZScene(scene)
            sceneCache.setObject(scene, forKey: cacheKey)
            return ResolvedDeviceModel(
                scene: scene,
                sourceURL: storeURL,
                source: .cached(storeURL),
                tier: .cached
            )
        }

        // 1b. Check if user configured a 1024px transparent product preview image
        if let previewImage = await DeviceModelStore.shared.getPreviewImage(for: device.stableKey) {
            let previewURL = await DeviceModelStore.shared.previewFileURL(for: device.stableKey)
            let cardScene = DeviceCategoryModelBuilder.buildProductImageCard(image: previewImage)
            sceneCache.setObject(cardScene, forKey: cacheKey)
            return ResolvedDeviceModel(
                scene: cardScene,
                sourceURL: previewURL,
                source: .cached(previewURL),
                tier: .custom
            )
        }

        // 2 & 3. Tier 2: Category Stand-in
        let standIn = resolveCategoryStandIn(for: device)
        sceneCache.setObject(standIn.scene, forKey: cacheKey)
        return standIn
    }

    /// Resolves only the category stand-in for a device (bypassing any Tier 1 exact cache).
    public func resolveCategoryStandIn(for device: DeviceIdentity) -> ResolvedDeviceModel {
        // Step 2a: Look for category USDZ at Resources/Models/Categories/<kind>.usdz
        if let categoryURL = findCategoryUSDZ(for: device.kind),
           let scene = try? SCNScene(url: categoryURL, options: nil) {
            Self.postProcessUSDZScene(scene)
            return ResolvedDeviceModel(
                scene: scene,
                sourceURL: categoryURL,
                source: .categoryUSDZ(categoryURL),
                tier: .categoryStandIn
            )
        }

        // Step 2b: Fallbacks
        // All device kinds use stylized procedural 3D models from SceneKit primitives (no flat cards)
        let primitiveScene = DeviceCategoryModelBuilder.buildProceduralModel(for: device.kind)
        return ResolvedDeviceModel(
            scene: primitiveScene,
            sourceURL: nil,
            source: .proceduralStandIn(device.kind),
            tier: .categoryStandIn
        )
    }

    // MARK: - SceneKit Material & Lighting Post-Processing

    public static func postProcessUSDZScene(_ scene: SCNScene) {
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let geometry = node.geometry else { return }
            for material in geometry.materials {
                material.lightingModel = .physicallyBased

                let matName = (material.name ?? "").lowercased()
                let nodeName = (node.name ?? "").lowercased()

                // Transparent glass & smoked-glass validation
                if matName.contains("smoke_glass") || nodeName.contains("smoke_glass") {
                    material.transparency = 0.62
                    material.isDoubleSided = true
                    material.blendMode = .alpha
                    material.roughness.contents = 0.15
                    material.metalness.contents = 0.10
                } else if matName.contains("glass") || nodeName.contains("glass") {
                    material.transparency = 0.35
                    material.isDoubleSided = true
                    material.blendMode = .alpha
                    material.roughness.contents = 0.05
                    material.metalness.contents = 0.05
                }

                // Emissive parts (emerald status LEDs, screens)
                if matName.contains("emerald") || matName.contains("emissive") || matName.contains("led") || matName.contains("screen") ||
                   nodeName.contains("emerald") || nodeName.contains("emissive") || nodeName.contains("led") || nodeName.contains("screen") {
                    if material.emission.contents == nil || (material.emission.contents as? NSColor) == NSColor.black {
                        material.emission.contents = NSColor(calibratedRed: 0.1, green: 0.9, blue: 0.6, alpha: 1.0)
                    }
                    material.emission.intensity = 1.2
                }
            }
        }

        // Soft environment map for realistic metallic PBR reflections
        if scene.lightingEnvironment.contents == nil {
            scene.lightingEnvironment.contents = createSoftEnvironmentMap()
            scene.lightingEnvironment.intensity = 1.0
        }
    }

    private static func createSoftEnvironmentMap() -> NSImage {
        let size = NSSize(width: 256, height: 128)
        let image = NSImage(size: size)
        image.lockFocus()
        let gradient = NSGradient(colors: [
            NSColor(calibratedWhite: 0.95, alpha: 1.0),
            NSColor(calibratedWhite: 0.65, alpha: 1.0),
            NSColor(calibratedWhite: 0.25, alpha: 1.0)
        ])
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 90)
        image.unlockFocus()
        return image
    }

    // MARK: - Preview PNG Lookup

    public func findPreviewImage(for kind: DeviceKind) -> NSImage? {
        if let data = findPreviewPNGData(for: kind) {
            return NSImage(data: data)
        }
        return nil
    }

    public func findPreviewPNGData(for kind: DeviceKind) -> Data? {
        let candidateNames = fileNames(for: kind)
        let subdirectories = [
            "Models/Previews",
            "Resources/Models/Previews",
            "Previews",
            ""
        ]

        for name in candidateNames {
            for subDir in subdirectories {
                if let url = Bundle.main.url(
                    forResource: name,
                    withExtension: "png",
                    subdirectory: subDir.isEmpty ? nil : subDir
                ), let data = try? Data(contentsOf: url) {
                    return data
                }
            }

            if let resourceURL = Bundle.main.resourceURL {
                let candidatePaths = [
                    resourceURL.appendingPathComponent("Models/Previews/\(name).png"),
                    resourceURL.appendingPathComponent("Resources/Models/Previews/\(name).png"),
                    resourceURL.appendingPathComponent("\(name).png")
                ]
                for path in candidatePaths {
                    if let data = try? Data(contentsOf: path) {
                        return data
                    }
                }
            }
        }

        let localSearchDirectories = [
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("liquiddinamo/Resources/Models/Previews"),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("LiquidDynamo/Resources/Models/Previews"),
            URL(fileURLWithPath: "liquiddinamo/Resources/Models/Previews"),
            URL(fileURLWithPath: "LiquidDynamo/Resources/Models/Previews")
        ]

        for base in localSearchDirectories {
            for name in candidateNames {
                let localURL = base.appendingPathComponent("\(name).png")
                if let data = try? Data(contentsOf: localURL) {
                    return data
                }
            }
        }

        return nil
    }

    // MARK: - Category USDZ File Lookup

    /// Searches for a category USDZ file in the application bundle and project resource paths.
    public func findCategoryUSDZ(for kind: DeviceKind) -> URL? {
        let candidateNames = fileNames(for: kind)

        // 1. Check inside Bundle.main under "Models/Categories" and "Resources/Models/Categories"
        let subdirectories = [
            "Models/Categories",
            "Resources/Models/Categories",
            "Categories",
            ""
        ]

        for name in candidateNames {
            for subDir in subdirectories {
                if let url = Bundle.main.url(
                    forResource: name,
                    withExtension: "usdz",
                    subdirectory: subDir.isEmpty ? nil : subDir
                ), FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }

            // Direct check in Bundle.main resourceURL
            if let resourceURL = Bundle.main.resourceURL {
                let candidatePaths = [
                    resourceURL.appendingPathComponent("Models/Categories/\(name).usdz"),
                    resourceURL.appendingPathComponent("Resources/Models/Categories/\(name).usdz"),
                    resourceURL.appendingPathComponent("\(name).usdz")
                ]
                for path in candidatePaths {
                    if FileManager.default.fileExists(atPath: path.path) {
                        return path
                    }
                }
            }
        }

        // 2. Development / Local workspace fallback (if running from source or debug build)
        let localSearchDirectories = [
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("liquiddinamo/Resources/Models/Categories"),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("LiquidDynamo/Resources/Models/Categories"),
            URL(fileURLWithPath: "liquiddinamo/Resources/Models/Categories"),
            URL(fileURLWithPath: "LiquidDynamo/Resources/Models/Categories")
        ]

        for base in localSearchDirectories {
            for name in candidateNames {
                let localURL = base.appendingPathComponent("\(name).usdz")
                if FileManager.default.fileExists(atPath: localURL.path) {
                    return localURL
                }
            }
        }

        return nil
    }

    /// Candidate filename variations for each kind to make dropping in models foolproof.
    public func fileNames(for kind: DeviceKind) -> [String] {
        switch kind {
        case .airpods:
            return ["airpods", "AirPods"]
        case .earbuds:
            return ["earbuds", "Earbuds", "airpods", "AirPods"]
        case .earphones:
            return ["earphones", "Earphones", "earbuds"]
        case .neckband:
            return ["neckband", "Neckband", "headphones", "Headphones"]
        case .headphones:
            return ["headphones", "Headphones"]
        case .speaker:
            return ["speaker", "Speaker"]
        case .ssdDrive:
            return ["ssd_drive", "ssdDrive", "drive", "SSD / Drive", "ssd", "external_drive"]
        case .usbStick:
            return ["usb_stick", "usbStick", "USB Flash Drive", "usbstick", "usb"]
        case .mouse:
            return ["mouse", "Mouse"]
        case .trackpad:
            return ["trackpad", "Trackpad"]
        case .keyboard:
            return ["keyboard", "Keyboard"]
        case .phone:
            return ["phone", "Phone", "iphone", "iPhone"]
        case .androidPhone:
            return ["android_phone", "androidPhone", "android", "Android"]
        case .tablet:
            return ["tablet", "Tablet", "ipad", "iPad"]
        case .monitor:
            return ["monitor", "Monitor", "display", "Display"]
        case .gameController:
            return ["gamepad", "game_controller", "gameController", "controller", "Game Controller"]
        case .printer:
            return ["printer", "Printer"]
        case .charger:
            return ["charger", "Charger", "power_adapter", "Power Adapter", "magsafe", "powerplug"]
        case .generic:
            return ["generic", "generic_device", "Generic"]
        }
    }

    // MARK: - Cache Invalidation

    public func clearMemoryCache() {
        sceneCache.removeAllObjects()
    }
}
