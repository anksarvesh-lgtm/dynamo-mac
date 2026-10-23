//
//  LiquidProductivityDashboardView.swift
//  LiquidDynamo
//
//  Manual-open productivity and system dashboard inside the transparent liquid mass.
//  Strict Liquid UI rules: no cards, rectangles, panels, widgets, or pill containers.
//  All content flows organically outside the physical notch zone.
//

import AppKit
import Defaults
import SceneKit
import SwiftUI

public struct LiquidProductivityDashboardView: View {
    @ObservedObject var statsService = SystemStatsService.shared
    @ObservedObject var throughputService = NetworkThroughputService.shared
    @ObservedObject var connectionService = ConnectionStatusService.shared
    @ObservedObject var wifiService = WiFiInfoService.shared
    @ObservedObject var shelfState = ShelfStateViewModel.shared
    @ObservedObject var deviceMonitor = DeviceMonitor.shared
    @ObservedObject var clipboardService = ClipboardHistoryService.shared
    @ObservedObject var safeArea = NotchSafeAreaEngine.shared
    @ObservedObject var renderer = SceneKitDeviceRenderer.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @ObservedObject var brightnessService = MultiDisplayBrightnessService.shared

    @Default(.showDashboardSystemInfo) var showSystemInfo
    @Default(.showDashboardDropper) var showDropper
    @Default(.showDashboardClipboard) var showClipboard
    @Default(.showDashboardDevices) var showDevices

    @State private var selectedDeviceKey: String?
    @State private var hoveredControlId: String?

    public init() {}

    public var body: some View {
        let geom = safeArea.currentGeometry

        VStack(spacing: 0) {
            // MARK: - Notch Zone (Physically empty, content strictly in wing slots)
            if geom.isNotched {
                HStack(spacing: 0) {
                    leftWingHeader(width: max(0, geom.wingWidth))
                    Color.clear
                        .frame(width: geom.rawNotchWidth, height: geom.rawNotchHeight)
                    rightWingHeader(width: max(0, geom.wingWidth))
                }
                .frame(height: max(geom.rawNotchHeight, 32))
            } else {
                nonNotchedHeader
                    .frame(height: 34)
            }

            // MARK: - Liquid Mass Flowing Regions (Outside the notch)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    // 1. System Information Region (CPU, RAM, Network)
                    if showSystemInfo {
                        systemInformationRegion
                    }

                    // 2. Quick App Shortcuts Region
                    quickAppShortcutsRegion

                    // 3. Connected Devices with 3D Models & External Device Controls
                    if showDevices && !deviceMonitor.activeDevices.isEmpty {
                        connectedDevicesRegion
                    }

                    // 4. Temporary Dropper Region
                    if showDropper {
                        dropperRegion
                    }

                    // 5. Clipboard History Region (Last 5 copied texts)
                    if showClipboard {
                        clipboardRegion
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 14)
            }
        }
        .onAppear {
            renderer.resumeRendering()
            if let first = deviceMonitor.activeDevices.keys.first {
                selectedDeviceKey = first
                loadDeviceModel(for: deviceMonitor.activeDevices[first]!)
            }
        }
        .onDisappear {
            renderer.pauseRendering()
        }
        .onChange(of: deviceMonitor.activeDevices) { _, newDevices in
            if let current = selectedDeviceKey, newDevices[current] == nil {
                selectedDeviceKey = newDevices.keys.first
                if let nextKey = selectedDeviceKey, let nextDevice = newDevices[nextKey] {
                    loadDeviceModel(for: nextDevice)
                } else {
                    renderer.dissolveAndClear()
                }
            } else if selectedDeviceKey == nil, let first = newDevices.keys.first {
                selectedDeviceKey = first
                loadDeviceModel(for: newDevices[first]!)
            }
        }
    }

    // MARK: - Wings Headers (Outside the notch cutout)

    @ViewBuilder
    private func leftWingHeader(width: CGFloat) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "cpu")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(cpuColor(statsService.overallCPU))

            Text("CPU \(Int(statsService.overallCPU))%")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(cpuColor(statsService.overallCPU))

            Spacer(minLength: 0)
        }
        .frame(width: width, alignment: .leading)
        .clipped()
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func rightWingHeader(width: CGFloat) -> some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)

            Image(systemName: "network")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.cyan)

            Text(formatNetworkSpeedText(download: throughputService.downloadBytesPerSecond, upload: throughputService.uploadBytesPerSecond))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
        }
        .frame(width: width, alignment: .trailing)
        .clipped()
        .padding(.horizontal, 8)
    }

    private var nonNotchedHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text("Liquid Island")
                    .font(.system(size: 11, weight: .bold))
            }

            Spacer()

            Text("\(statsService.formattedDate) • \(statsService.formattedTime)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - 1. System Information Region

    private var systemInformationRegion: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section Title with live thermal indicator
            HStack(spacing: 8) {
                Premium3DIconView(.cpu, size: 14, interactive: false, continuousRotation: true)

                Text("System & Network")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.primary)

                Spacer()

                // Thermal state (100% public non-invented API)
                HStack(spacing: 4) {
                    Image(systemName: statsService.thermalStateIcon)
                        .font(.system(size: 10, weight: .semibold))
                    Text(statsService.thermalStateTitle)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(statsService.thermalStateColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(OrganicDropletShape().fill(statsService.thermalStateColor.opacity(0.12)))
            }

            // Flowing metrics row 1: CPU and RAM usage
            HStack(spacing: 24) {
                // CPU
                VStack(alignment: .leading, spacing: 2) {
                    Text("CPU")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("\(Int(statsService.overallCPU))%")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(cpuColor(statsService.overallCPU))
                }

                // RAM with memory pressure
                VStack(alignment: .leading, spacing: 2) {
                    Text("MEMORY")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                    HStack(spacing: 3) {
                        Text("\(statsService.formattedMemoryUsed)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                        Text("/ \(statsService.formattedMemoryAvailable) free")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 4)

            // Flowing metrics row 2: Network Throughput & Interface
            HStack(spacing: 14) {
                // Connection Interface + Network Name
                HStack(spacing: 5) {
                    Image(systemName: connectionService.interfaceType.iconName)
                        .font(.system(size: 11))
                        .foregroundColor(.cyan)

                    if let wifi = wifiService.currentInfo, connectionService.interfaceType == .wifi {
                        let ssidName = (wifi.ssid?.isEmpty == false) ? wifi.ssid! : "Wi-Fi"
                        Text(ssidName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if wifi.transmitRate > 0 {
                            Text("\(Int(wifi.transmitRate)) Mbps")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        if let ip = wifi.localIPv4, !ip.isEmpty {
                            Text("• \(ip)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                    } else {
                        Text(connectionService.interfaceType.displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }

                Spacer()

                // Live Download & Upload Speed
                HStack(spacing: 10) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.green)
                        Text(formattedSpeed(throughputService.downloadBytesPerSecond))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                    }

                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.blue)
                        Text(formattedSpeed(throughputService.uploadBytesPerSecond))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(.vertical, 6)
        .overlay(
            // Subtle organic liquid contour divider
            VStack {
                Spacer()
                OrganicDropletShape()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1.5)
            }
        )
    }

    // MARK: - 2. Connected Devices Region (Rotating 3D Models in Liquid Mass)

    private var connectedDevicesRegion: some View {
        let devices = deviceMonitor.sortedActiveDevices
        let activeDevice = devices.first { $0.stableKey == selectedDeviceKey } ?? devices.first

        return VStack(alignment: .leading, spacing: 8) {
            // Header: Device count and switcher
            HStack(spacing: 8) {
                Premium3DIconView(.desktopMac, size: 14, interactive: false, continuousRotation: true)

                Text("Connected Devices")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.primary)

                Text("\(devices.count)")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(OrganicDropletShape().fill(Color.white.opacity(0.12)))
                    .foregroundColor(.secondary)

                Spacer()

                // If multiple devices, show organic droplet switchers
                if devices.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(devices) { dev in
                            Button {
                                selectedDeviceKey = dev.stableKey
                                loadDeviceModel(for: dev)
                            } label: {
                                Image(systemName: dev.iconName)
                                    .font(.system(size: 10))
                                    .foregroundColor(dev.stableKey == activeDevice?.stableKey ? .white : .secondary.opacity(0.6))
                                    .padding(5)
                                    .background(
                                        OrganicDropletShape()
                                            .fill(dev.stableKey == activeDevice?.stableKey ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.06))
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(dev.displayName)
                        }
                    }
                }
            }

            // 3D View + Floating Information (Inside Liquid Mass, NOT in cards)
            if let device = activeDevice {
                HStack(alignment: .center, spacing: 14) {
                    // Reused single 3D SceneView (Slow rotation, 30fps capped)
                    Device3DRendererContainerView(renderer: renderer)
                        .frame(width: 80, height: 80)
                        .clipShape(OrganicDropletShape())
                        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)

                    // Floating Liquid Info
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(device.displayName)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Text(device.kind.rawValue)
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(OrganicDropletShape().fill(Color.white.opacity(0.1)))
                                .foregroundColor(.secondary)
                        }

                        // Category specific information
                        deviceSpecificDetailsView(device: device)
                    }

                    Spacer()

                    // Eject button for external storage
                    if device.kind == .ssdDrive || device.kind == .usbStick {
                        Button {
                            device.eject()
                        } label: {
                            Image(systemName: "eject.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.orange)
                                .padding(8)
                                .background(OrganicDropletShape().fill(Color.orange.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                        .help("Eject \(device.displayName)")
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
        }
        .padding(.vertical, 6)
        .overlay(
            VStack {
                Spacer()
                OrganicDropletShape()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1.5)
            }
        )
    }

    @ViewBuilder
    private func deviceSpecificDetailsView(device: DeviceIdentity) -> some View {
        let isAirPods = device.displayName.localizedCaseInsensitiveContains("AirPods")
            || device.model.localizedCaseInsensitiveContains("AirPods")
            || (device.kind == .earbuds && (device.leftBattery != nil || device.caseBattery != nil))

        if isAirPods {
            // AirPods → Show battery status and volume controls
            VStack(alignment: .leading, spacing: 6) {
                if let left = device.leftBattery, let right = device.rightBattery {
                    HStack(spacing: 8) {
                        HStack(spacing: 2) {
                            Text("L:")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                            Text("\(left)%")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        }
                        HStack(spacing: 2) {
                            Text("R:")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                            Text("\(right)%")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        }
                        if let caseBat = device.caseBattery {
                            HStack(spacing: 2) {
                                Text("Case:")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.secondary)
                                Text("\(caseBat)%")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            }
                        }
                    }
                    .foregroundColor(.primary)
                } else if let bat = device.batteryPercentage {
                    Text("Battery: \(bat)%")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.green)
                } else {
                    Text("Battery unavailable")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))
                }

                // Volume controls for AirPods
                LiquidDeviceVolumeControl()
            }
        } else {
            switch device.kind {
            case .airpods, .earbuds, .earphones, .headphones, .neckband:
                // Bluetooth headphones/earbuds → Show battery and volume information if available
                VStack(alignment: .leading, spacing: 6) {
                    if let bat = device.batteryPercentage {
                        Text("Battery: \(bat)% • \(device.connectionType.rawValue)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.green)
                    } else {
                        Text("Battery unavailable • \(device.connectionType.rawValue)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.7))
                    }

                    // Volume controls for Bluetooth headphones
                    LiquidDeviceVolumeControl()
                }

            case .speaker:
                // Wireless speakers → Show volume controls
                VStack(alignment: .leading, spacing: 6) {
                    if let bat = device.batteryPercentage {
                        Text("Battery: \(bat)% • \(device.connectionType.rawValue)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.green)
                    } else {
                        Text("Connected via \(device.connectionType.rawValue)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    // Volume controls for wireless speakers
                    LiquidDeviceVolumeControl()
                }

            case .androidPhone:
                // Android devices → Show battery status if available
                HStack(spacing: 6) {
                    Text("Connected via \(device.connectionType.rawValue)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    if let bat = device.batteryPercentage {
                        Text("• \(bat)% battery")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.green)
                    } else {
                        Text("• Battery unavailable")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }

            case .phone, .tablet:
                // iPhone/iPad → Show battery status if available
                HStack(spacing: 6) {
                    Text("Connected via \(device.connectionType.rawValue)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    if let bat = device.batteryPercentage {
                        Text("• \(bat)% battery")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.green)
                    } else {
                        Text("• Battery unavailable")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }

            case .monitor:
                // External displays → Show brightness controls if supported
                VStack(alignment: .leading, spacing: 6) {
                    if let res = device.resolution {
                        Text("\(res) @ \(Int(round(device.refreshRate ?? 60.0))) Hz")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    if let scaled = device.scaledResolution {
                        Text("UI scale: \(scaled)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    // Brightness controls for external display
                    LiquidDeviceBrightnessControl(device: device)
                }

            case .ssdDrive, .usbStick:
                // External Storage: Capacity, Used, Free, Filesystem
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if let used = device.formattedUsedSpace, let total = device.formattedCapacity {
                            Text("\(used) used of \(total)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.primary)
                        } else if let total = device.formattedCapacity {
                            Text("Capacity: \(total)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.primary)
                        }

                        if let fs = device.filesystem {
                            Text("(\(fs))")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }

                    if let free = device.formattedFreeSpace {
                        Text("\(free) free • \(device.connectionType.rawValue)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }

            case .charger:
                // Charger / Power Adapter → Show plugged port, wattage, live voltage/current and charging state
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.green)

                        Text(device.chargerPort ?? "Power Port")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.primary)

                        if let watts = device.chargerWatts, watts > 0 {
                            Text("\(watts)W")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.green)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.green.opacity(0.15)))
                        }
                    }

                    HStack(spacing: 6) {
                        if let volts = device.chargingVoltage, let amps = device.chargingCurrent, volts > 0 {
                            Text(String(format: "%.1fV • %.2fA", volts, amps))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        if let power = device.chargingPowerWatts, power > 0 {
                            Text(String(format: "(%.1fW)", power))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                        if let desc = device.chargingStatusDescription {
                            Text("• \(desc)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.green)
                        }
                    }
                }

            default:
                // Other connected devices (keyboard, mouse, gamepad, etc.) → Show only information provided by device
                HStack(spacing: 6) {
                    Text(device.connectionType.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)

                    if let bat = device.batteryPercentage {
                        Text("• \(bat)% battery")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                    } else {
                        Text("• Battery unavailable")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
            }
        }
    }

    private func loadDeviceModel(for device: DeviceIdentity) {
        let scene = DeviceModelResolver.shared.resolveCategoryStandIn(for: device).scene
        renderer.loadScene(scene)
    }

    // MARK: - 3. Temporary Dropper Region

    private var dropperRegion: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                Text("Dropper")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.primary)

                if !shelfState.items.isEmpty {
                    Text("\(shelfState.items.count)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(OrganicDropletShape().fill(Color.white.opacity(0.12)))
                        .foregroundColor(.secondary)

                    Spacer()

                    Button {
                        shelfState.clearAll()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                            Text("Clear")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.secondary.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Clear all items from dropper")
                } else {
                    Spacer()
                }
            }

            if shelfState.items.isEmpty {
                // Collapses to an organic drop when empty
                HStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("Drop files or browser images here")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .padding(.vertical, 6)
            } else {
                // Flowing items in organic droplet masks
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(shelfState.items) { item in
                            ShelfItemView(item: item)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.vertical, 6)
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: nil) { providers in
            shelfState.load(providers)
            return true
        }
        .overlay(
            VStack {
                Spacer()
                OrganicDropletShape()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1.5)
            }
        )
    }

    // MARK: - 4. Clipboard History Region

    private var clipboardRegion: some View {
        LiquidClipboardRegionView()
    }

    // MARK: - 5. Quick App Shortcuts Region

    private var quickAppShortcutsRegion: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Premium3DIconView(.stats, size: 14, interactive: false, continuousRotation: true)

                Text("Quick Shortcuts")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.primary)

                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(quickApps) { app in
                        Button {
                            launchApp(app)
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    OrganicDropletShape()
                                        .fill(Color.white.opacity(0.08))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            OrganicDropletShape()
                                                .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                                        )

                                    Premium3DIconView(
                                        name: app.iconName,
                                        size: 22,
                                        customTint: app.tintColor,
                                        interactive: true,
                                        continuousRotation: true
                                    )
                                }

                                Text(app.name)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 48)
                        }
                        .buttonStyle(.plain)
                        .help("Open \(app.name)")
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.vertical, 6)
        .overlay(
            VStack {
                Spacer()
                OrganicDropletShape()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1.5)
            }
        )
    }

    private let quickApps: [QuickAppItem] = [
        QuickAppItem(id: "finder", name: "Finder", iconName: "folder.fill", tintColor: .blue, bundleId: "com.apple.finder"),
        QuickAppItem(id: "safari", name: "Safari", iconName: "safari.fill", tintColor: .cyan, bundleId: "com.apple.Safari"),
        QuickAppItem(id: "terminal", name: "Terminal", iconName: "terminal.fill", tintColor: .green, bundleId: "com.apple.Terminal"),
        QuickAppItem(id: "notes", name: "Notes", iconName: "note.text", tintColor: .yellow, bundleId: "com.apple.Notes"),
        QuickAppItem(id: "settings", name: "Settings", iconName: "gearshape.fill", tintColor: .gray, bundleId: "com.apple.systempreferences"),
        QuickAppItem(id: "music", name: "Music", iconName: "music.note", tintColor: .red, bundleId: "com.apple.Music"),
        QuickAppItem(id: "calculator", name: "Calculator", iconName: "plus.forwardslash.minus", tintColor: .orange, bundleId: "com.apple.calculator"),
        QuickAppItem(id: "mail", name: "Mail", iconName: "envelope.fill", tintColor: .blue, bundleId: "com.apple.mail")
    ]

    private func launchApp(_ app: QuickAppItem) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
        }
    }

    // MARK: - Formatters & Helpers

    private func cpuColor(_ load: Double) -> Color {
        if load >= 90 {
            return .red
        } else if load >= 65 {
            return .orange
        } else if load >= 35 {
            return .yellow
        } else {
            return .green
        }
    }

    private func formatNetworkSpeedText(download: Double, upload: Double) -> String {
        let primary = download > 500 ? download : max(download, upload)
        let bits = primary * 8.0
        if bits >= 1_000_000_000 {
            return String(format: "%.1fGbps", bits / 1_000_000_000.0)
        } else if bits >= 1_000_000 {
            return String(format: "%.1fMbps", bits / 1_000_000.0)
        } else if bits >= 1_000 {
            return String(format: "%.0fkbps", bits / 1_000.0)
        } else {
            return "0kbps"
        }
    }

    private func formattedSpeed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond <= 0 { return "0 B/s" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }
}

// MARK: - Quick App Item Model

public struct QuickAppItem: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let iconName: String
    public let tintColor: Color
    public let bundleId: String
}

// MARK: - Liquid Device Volume Control

private struct LiquidDeviceVolumeControl: View {
    @ObservedObject var volumeManager = VolumeManager.shared

    var body: some View {
        HStack(spacing: 8) {
            Button {
                volumeManager.toggleMuteAction()
            } label: {
                Image(systemName: volumeManager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(volumeManager.isMuted ? .red : .accentColor)
                    .frame(width: 22, height: 22)
                    .background(OrganicDropletShape().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help(volumeManager.isMuted ? "Unmute" : "Mute")

            GeometryReader { geo in
                let progress = CGFloat(volumeManager.isMuted ? 0 : volumeManager.rawVolume)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 6)

                    Capsule()
                        .fill(volumeManager.isMuted ? Color.gray : Color.accentColor)
                        .frame(width: max(0, min(geo.size.width * progress, geo.size.width)), height: 6)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let percent = max(0, min(1, gesture.location.x / geo.size.width))
                            volumeManager.setAbsolute(Float32(percent))
                        }
                )
            }
            .frame(width: 110, height: 18)

            Text("\(Int((volumeManager.isMuted ? 0 : volumeManager.rawVolume) * 100))%")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Liquid Device Brightness Control

private struct LiquidDeviceBrightnessControl: View {
    @ObservedObject var brightnessService = MultiDisplayBrightnessService.shared
    let device: DeviceIdentity

    private var targetDisplay: ManagedDisplay? {
        if let d = brightnessService.displays.first(where: { "display_\($0.id)" == device.stableKey }) {
            return d
        }
        if let d = brightnessService.displays.first(where: { $0.name == device.displayName }) {
            return d
        }
        if device.displayName.contains("Built-in") || device.model.contains("Built-in") {
            return brightnessService.displays.first(where: { $0.isBuiltIn })
        }
        return brightnessService.displays.first
    }

    var body: some View {
        if let display = targetDisplay {
            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.yellow)
                    .frame(width: 22, height: 22)
                    .background(OrganicDropletShape().fill(Color.white.opacity(0.08)))

                GeometryReader { geo in
                    let progress = CGFloat(display.brightness)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 6)

                        Capsule()
                            .fill(Color.yellow.opacity(0.85))
                            .frame(width: max(0, min(geo.size.width * progress, geo.size.width)), height: 6)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                let percent = Float(max(0, min(1, gesture.location.x / geo.size.width)))
                                brightnessService.setBrightness(percent, for: display)
                            }
                    )
                }
                .frame(width: 110, height: 18)

                Text("\(Int(display.brightness * 100))%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(width: 32, alignment: .trailing)
            }
            .padding(.vertical, 2)
        } else {
            Text("Hardware brightness control unsupported")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary.opacity(0.7))
        }
    }
}

// MARK: - SceneKit Reused View Representable

private struct Device3DRendererContainerView: NSViewRepresentable {
    let renderer: SceneKitDeviceRenderer

    func makeNSView(context: Context) -> SCNView {
        renderer.scnView
    }

    func updateNSView(_ nsView: SCNView, context: Context) {}
}
