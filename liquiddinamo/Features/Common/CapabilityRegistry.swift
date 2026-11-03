//
//  CapabilityRegistry.swift
//  LiquidDynamo
//
//  Created for Production Dynamic Island Architecture.
//  Strictly enforces technical honesty, public API compliance, and permission boundaries.
//

import Foundation
import Combine
import IOKit.ps
import CoreBluetooth
import AVFoundation

public enum FeatureClassification: String, CaseIterable, Codable {
    case native = "Native"
    case custom = "Custom"
    case permissionDependent = "Permission-Dependent"
    case integrationDependent = "Integration-Dependent"
    case unavailable = "Unavailable"
}

public struct CapabilityDescriptor: Identifiable {
    public let id: String
    public let name: String
    public let classification: FeatureClassification
    public let publicAPI: String
    public let requiredPermission: String?
    public let isAvailable: Bool
    public let notes: String
}

@MainActor
public final class CapabilityRegistry: ObservableObject {
    public static let shared = CapabilityRegistry()
    
    @Published public private(set) var capabilities: [CapabilityDescriptor] = []
    
    private init() {
        registerAllCapabilities()
    }
    
    private func registerAllCapabilities() {
        capabilities = [
            // MARK: - Native Features
            CapabilityDescriptor(
                id: "window.overlay",
                name: "Persistent Notch-Anchored Overlay Window",
                classification: .native,
                publicAPI: "AppKit (NSWindow, NSWindow.Level.floating, NSScreen.auxiliaryTopLeftArea)",
                requiredPermission: nil,
                isAvailable: true,
                notes: "Single transparent window anchored to hardware notch or simulated top safe area."
            ),
            CapabilityDescriptor(
                id: "power.magsafe",
                name: "Power Adapter & Battery Telemetry",
                classification: .native,
                publicAPI: "IOKit.ps (IOPSCopyExternalPowerAdapterDetails, IOPSCopyPowerSourcesInfo)",
                requiredPermission: nil,
                isAvailable: true,
                notes: "Provides verified power adapter wattage, charging status, and battery percentage."
            ),
            CapabilityDescriptor(
                id: "system.thermal",
                name: "System Thermal State",
                classification: .native,
                publicAPI: "Foundation (ProcessInfo.processInfo.thermalState)",
                requiredPermission: nil,
                isAvailable: true,
                notes: "Categorical thermal status (nominal, fair, serious, critical). No private SMC calls."
            ),
            CapabilityDescriptor(
                id: "system.metrics",
                name: "System CPU & Memory Metrics",
                classification: .native,
                publicAPI: "Darwin/mach (host_statistics64, host_cpu_load_info)",
                requiredPermission: nil,
                isAvailable: true,
                notes: "Throttled sampling of system-wide CPU usage, memory pressure, and physical memory."
            ),
            CapabilityDescriptor(
                id: "network.throughput",
                name: "Network Interface Throughput",
                classification: .native,
                publicAPI: "Darwin (getifaddrs, if_data)",
                requiredPermission: nil,
                isAvailable: true,
                notes: "Real-time byte counter deltas for active network interfaces."
            ),
            CapabilityDescriptor(
                id: "app.notifications",
                name: "LiquidDynamo Local Notifications",
                classification: .native,
                publicAPI: "UserNotifications (UNUserNotificationCenter)",
                requiredPermission: "Notifications",
                isAvailable: true,
                notes: "Local notifications triggered and managed by LiquidDynamo itself."
            ),
            
            // MARK: - Custom Features
            CapabilityDescriptor(
                id: "render.liquid_glass",
                name: "Liquid Glass Material & SDF Shaders",
                classification: .custom,
                publicAPI: "SwiftUI Material, Metal Shading Language, CoreAnimation",
                requiredPermission: nil,
                isAvailable: true,
                notes: "Smoked charcoal glass with directional sheen, Fresnel reflection, and chromatic dispersion."
            ),
            CapabilityDescriptor(
                id: "ui.carousel",
                name: "Adaptive 3-Slide Utility Carousel",
                classification: .custom,
                publicAPI: "SwiftUI View architecture",
                requiredPermission: nil,
                isAvailable: true,
                notes: "Productivity, System Tools, and Watcher slides with dynamic Media Player slide promotion."
            ),
            CapabilityDescriptor(
                id: "expansion.morph",
                name: "In-Place Dynamic Island Detail Expansion",
                classification: .custom,
                publicAPI: "SwiftUI GeometryReader, Spring Animations",
                requiredPermission: nil,
                isAvailable: true,
                notes: "Expands within central island to 2x compact height while keeping wings fixed."
            ),
            
            // MARK: - Permission-Dependent Features
            CapabilityDescriptor(
                id: "dropper.screen_sample",
                name: "Color Dropper Screen Sampling",
                classification: .permissionDependent,
                publicAPI: "CoreGraphics / ScreenCaptureKit",
                requiredPermission: "Screen Recording",
                isAvailable: CGPreflightScreenCaptureAccess(),
                notes: "Requires user permission to read pixels under the cursor for hex/RGB inspection."
            ),
            CapabilityDescriptor(
                id: "media.automation",
                name: "External Music Player Automation (Music/Spotify)",
                classification: .permissionDependent,
                publicAPI: "AppleScript / ScriptingBridge (NSAppleScript)",
                requiredPermission: "Automation (System Events / Music)",
                isAvailable: true,
                notes: "Requires user automation consent to query track details and dispatch playback controls."
            ),
            CapabilityDescriptor(
                id: "clipboard.history",
                name: "Clipboard History Tracking",
                classification: .permissionDependent,
                publicAPI: "AppKit (NSPasteboard.general)",
                requiredPermission: "Accessibility (for background monitoring)",
                isAvailable: true,
                notes: "Tracks pasteboard changes locally without cloud transmission."
            ),
            
            // MARK: - Integration-Dependent Features
            CapabilityDescriptor(
                id: "bluetooth.audio",
                name: "Bluetooth Audio Accessory State",
                classification: .integrationDependent,
                publicAPI: "CoreAudio / CoreBluetooth",
                requiredPermission: "Bluetooth",
                isAvailable: true,
                notes: "Monitors active connected audio peripherals and battery level when exposed via GATT."
            ),
            CapabilityDescriptor(
                id: "phone.bridge",
                name: "Phone Bridge Device Pairing",
                classification: .integrationDependent,
                publicAPI: "Network / Local USB daemon",
                requiredPermission: "Local Network",
                isAvailable: true,
                notes: "Connects to companion mobile client over verified local connection."
            ),
            
            // MARK: - Unavailable (Public API Compliance)
            CapabilityDescriptor(
                id: "system.global_notifications",
                name: "Global Third-Party Notification Center Scraping",
                classification: .unavailable,
                publicAPI: "None (Private SQLite / UI Scraping prohibited)",
                requiredPermission: nil,
                isAvailable: false,
                notes: "Apple provides no public API to intercept arbitrary third-party notification center banners."
            ),
            CapabilityDescriptor(
                id: "hardware.smc_temperatures",
                name: "Internal SMC Sensor Fan RPM & Temperatures",
                classification: .unavailable,
                publicAPI: "None (Private AppleSMC / IOPlatformPluginFamily prohibited)",
                requiredPermission: nil,
                isAvailable: false,
                notes: "Unsanctioned private hardware keys. Handled via public ProcessInfo.thermalState."
            ),
            CapabilityDescriptor(
                id: "system.global_mic_camera_snooping",
                name: "Global Third-Party Microphone & Camera Spying",
                classification: .unavailable,
                publicAPI: "None (TCC private states prohibited)",
                requiredPermission: nil,
                isAvailable: false,
                notes: "Only LiquidDynamo's own AVFoundation/ScreenCaptureKit sessions are tracked."
            )
        ]
    }
    
    public func isFeatureAvailable(_ id: String) -> Bool {
        guard let item = capabilities.first(where: { $0.id == id }) else { return false }
        return item.isAvailable && item.classification != .unavailable
    }
}

