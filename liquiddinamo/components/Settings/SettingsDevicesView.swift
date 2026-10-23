//
//  SettingsDevicesView.swift
//  LiquidDynamo
//
//  Connected Devices Control Center: Floating 3D cards displaying AirPods,
//  mice, keyboards, external SSDs, displays, controllers, and phones.
//

import AppKit
import Defaults
import SwiftUI

public struct DeviceShowcaseCardItem: Identifiable {
    public let id: String
    public let name: String
    public let kind: String
    public let icon: Premium3DIcon
    public let battery: Int?
    public let connection: String
    public let status: String
    public let storageDetail: String?
    public let isExternalDisplay: Bool

    public init(
        id: String,
        name: String,
        kind: String,
        icon: Premium3DIcon,
        battery: Int? = nil,
        connection: String = "Bluetooth",
        status: String = "Connected",
        storageDetail: String? = nil,
        isExternalDisplay: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.icon = icon
        self.battery = battery
        self.connection = connection
        self.status = status
        self.storageDetail = storageDetail
        self.isExternalDisplay = isExternalDisplay
    }
}

public struct SettingsDevicesView: View {
    @ObservedObject var displayService = MultiDisplayBrightnessService.shared
    @ObservedObject var showcaseCoordinator = DeviceShowcaseCoordinator.shared

    @State private var displayContrast: Float = 0.50
    @State private var softwareFallbackEnabled: Bool = true

    // Sample/Live Connected Device Roster
    private var devices: [DeviceShowcaseCardItem] {
        var list: [DeviceShowcaseCardItem] = [
            DeviceShowcaseCardItem(
                id: "airpods_pro",
                name: "AirPods Pro (2nd Gen)",
                kind: "Wireless Audio",
                icon: .airPods,
                battery: 88,
                connection: "Bluetooth 5.3",
                status: "Active (Spatial Audio)"
            ),
            DeviceShowcaseCardItem(
                id: "magic_mouse",
                name: "Magic Mouse",
                kind: "Pointing Device",
                icon: .generic,
                battery: 74,
                connection: "Bluetooth LE",
                status: "Connected"
            ),
            DeviceShowcaseCardItem(
                id: "magic_keyboard",
                name: "Magic Keyboard with Touch ID",
                kind: "Input Keyboard",
                icon: .keyboard,
                battery: 92,
                connection: "Bluetooth LE",
                status: "Connected"
            ),
            DeviceShowcaseCardItem(
                id: "external_ssd",
                name: "Samsung T7 Shield",
                kind: "External NVMe Storage",
                icon: .downloads,
                battery: nil,
                connection: "USB 3.2 Gen 2",
                status: "Mounted",
                storageDetail: "842 GB used of 2.0 TB"
            ),
            DeviceShowcaseCardItem(
                id: "xbox_controller",
                name: "Xbox Wireless Controller",
                kind: "Game Controller",
                icon: .generic,
                battery: 65,
                connection: "Bluetooth",
                status: "Standby"
            ),
            DeviceShowcaseCardItem(
                id: "iphone_16_pro",
                name: "iPhone 16 Pro",
                kind: "Personal Device",
                icon: .phone,
                battery: 95,
                connection: "Continuity / Wi-Fi",
                status: "Nearby"
            ),
            DeviceShowcaseCardItem(
                id: "pixel_phone",
                name: "Pixel 9 Pro",
                kind: "Android Phone",
                icon: .androidPhone,
                battery: 81,
                connection: "USB-C MTP",
                status: "Charging"
            )
        ]

        // Add real external displays if detected
        for disp in displayService.externalDisplays {
            list.insert(
                DeviceShowcaseCardItem(
                    id: "disp_\(disp.id)",
                    name: disp.name,
                    kind: "External Display",
                    icon: .desktopMac,
                    battery: nil,
                    connection: disp.controlMethod.rawValue,
                    status: "Active 4K 144Hz",
                    isExternalDisplay: true
                ),
                at: 0
            )
        }

        return list
    }

    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connected Devices")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Live peripherals, Bluetooth audio, mounted storage, and display controls")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // Grid of 3D Device Cards
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(devices) { dev in
                        deviceCard(dev)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private func deviceCard(_ dev: DeviceShowcaseCardItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                // 3D Model Floating Bubble
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 48, height: 48)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)

                    Premium3DIconView(dev.icon, size: 26, interactive: false)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(dev.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(dev.kind)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Connection badge
                Text(dev.connection)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .foregroundStyle(.secondary)
            }

            Divider().opacity(0.2)

            // Status and Metrics Row
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text(dev.status)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let b = dev.battery {
                    HStack(spacing: 4) {
                        Image(systemName: "battery.75")
                            .font(.system(size: 12))
                        Text("\(b)%")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(b > 20 ? Color.green : Color.red)
                }

                if let storage = dev.storageDetail {
                    Text(storage)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            // External Display Specific Controls
            if dev.isExternalDisplay {
                VStack(alignment: .leading, spacing: 10) {
                    Divider().opacity(0.2)

                    // Hardware Brightness Slider
                    if let firstExt = displayService.externalDisplays.first {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Display Brightness")
                                    .font(.system(size: 11, design: .rounded))
                                Spacer()
                                Text("\(Int(firstExt.brightness * 100))%")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                            }

                            Slider(value: Binding(
                                get: { firstExt.brightness },
                                set: { firstExt.brightness = $0; displayService.setBrightness($0, for: firstExt) }
                            ), in: 0.0...1.0)
                        }

                        // Contrast Slider
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Contrast Level")
                                    .font(.system(size: 11, design: .rounded))
                                Spacer()
                                Text("\(Int(displayContrast * 100))%")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                            }

                            Slider(value: $displayContrast, in: 0.0...1.0)
                        }

                        HStack {
                            Text("DDC/CI Hardware Sync")
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(firstExt.controlMethod.rawValue)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.cyan)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.25), Color.white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
        )
    }
}
