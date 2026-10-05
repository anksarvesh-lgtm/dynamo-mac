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
            return ResolvedDeviceModel(
                scene: scene,
                sourceURL: categoryURL,
                source: .categoryUSDZ(categoryURL),
                tier: .categoryStandIn
            )
        }

        // Step 2b: Fallbacks
        // For storage devices: flat card with system icon from NSWorkspace
        if device.connectionType == .storage || device.kind == .ssdDrive || device.kind == .usbStick {
            let cardScene = DeviceCategoryModelBuilder.buildStorageFlatCard(for: device)
            return ResolvedDeviceModel(
                scene: cardScene,
                sourceURL: nil,
                source: .storageFlatCard,
                tier: .categoryStandIn
            )
        }

        // For other devices: stylized procedural model from SceneKit primitives
        let primitiveScene = DeviceCategoryModelBuilder.buildProceduralModel(for: device.kind)
        return ResolvedDeviceModel(
            scene: primitiveScene,
            sourceURL: nil,
            source: .proceduralStandIn(device.kind),
            tier: .categoryStandIn
        )
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
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("LiquidDynamo/Resources/Models/Categories"),
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
    private func fileNames(for kind: DeviceKind) -> [String] {
        switch kind {
        case .earbuds:
            return ["earbuds", "Earbuds"]
        case .headphones:
            return ["headphones", "Headphones"]
        case .speaker:
            return ["speaker", "Speaker"]
        case .ssdDrive:
            return ["ssd_drive", "ssdDrive", "drive", "SSD / Drive", "ssd"]
        case .usbStick:
            return ["usb_stick", "usbStick", "USB Flash Drive", "usbstick", "usb"]
        case .mouse:
            return ["mouse", "Mouse"]
        case .keyboard:
            return ["keyboard", "Keyboard"]
        case .phone:
            return ["phone", "Phone"]
        case .generic:
            return ["generic", "generic_device", "Generic"]
        }
    }

    // MARK: - Cache Invalidation

    public func clearMemoryCache() {
        sceneCache.removeAllObjects()
    }
}
