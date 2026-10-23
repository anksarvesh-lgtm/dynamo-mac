//
//  DeviceMemoryRegistry.swift
//  LiquidDynamo
//
//  Maintains persistent device recognition memory:
//  - Saves identity, type, and preferred 3D visual asset on first connection
//  - Instantly recognizes returning hardware without rediscovering
//  - Persists locally in Application Support directory
//

import AppKit
import Combine
import Foundation

public struct DeviceMemoryEntry: Codable, Identifiable, Equatable {
    public var id: String { stableKey }
    public let stableKey: String
    public var displayName: String
    public var kind: String
    public var preferredVisualAsset: String
    public var firstSeenAt: Date
    public var lastSeenAt: Date
    public var customLabel: String?

    public init(
        stableKey: String,
        displayName: String,
        kind: String,
        preferredVisualAsset: String,
        firstSeenAt: Date = Date(),
        lastSeenAt: Date = Date(),
        customLabel: String? = nil
    ) {
        self.stableKey = stableKey
        self.displayName = displayName
        self.kind = kind
        self.preferredVisualAsset = preferredVisualAsset
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.customLabel = customLabel
    }
}

@MainActor
public final class DeviceMemoryRegistry: ObservableObject {
    public static let shared = DeviceMemoryRegistry()

    @Published public private(set) var entries: [String: DeviceMemoryEntry] = [:]

    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let bundleID = Bundle.main.bundleIdentifier ?? "com.agrigence.liquiddynamo"
        let folder = appSupport.appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.fileURL = folder.appendingPathComponent("device_memory_registry.json")

        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: DeviceMemoryEntry].self, from: data) else {
            return
        }
        self.entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    /// Remember a device upon detection
    public func remember(device: DeviceIdentity) {
        let key = device.stableKey
        if var existing = entries[key] {
            existing.lastSeenAt = Date()
            existing.displayName = device.displayName
            entries[key] = existing
        } else {
            let asset = resolvePreferredVisualAsset(for: device)
            let entry = DeviceMemoryEntry(
                stableKey: key,
                displayName: device.displayName,
                kind: device.kind.rawValue,
                preferredVisualAsset: asset,
                firstSeenAt: Date(),
                lastSeenAt: Date()
            )
            entries[key] = entry
        }
        save()
    }

    public func isRecognized(deviceKey: String) -> Bool {
        return entries[deviceKey] != nil
    }

    public func preferredVisualAsset(for device: DeviceIdentity) -> String {
        if let entry = entries[device.stableKey] {
            return entry.preferredVisualAsset
        }
        return resolvePreferredVisualAsset(for: device)
    }

    private func resolvePreferredVisualAsset(for device: DeviceIdentity) -> String {
        let nameLower = device.displayName.lowercased()
        switch device.kind {
        case .airpods:
            return "3d_airpods"
        case .earbuds:
            return "3d_earbuds"
        case .earphones:
            return "3d_earphones"
        case .headphones, .neckband:
            return "3d_headphones"
        case .speaker:
            return "3d_speaker"
        case .ssdDrive, .usbStick:
            return "3d_ssd"
        case .monitor:
            return "3d_monitor"
        case .mouse:
            return "3d_mouse"
        case .trackpad:
            return "3d_trackpad"
        case .keyboard:
            return "3d_keyboard"
        case .androidPhone:
            return "3d_android"
        case .phone:
            return "3d_phone"
        case .tablet:
            return "3d_tablet"
        case .gameController:
            return "3d_gamepad"
        case .printer:
            return "3d_printer"
        default:
            return "3d_generic"
        }
    }
}
