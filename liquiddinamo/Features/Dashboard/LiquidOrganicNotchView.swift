//
//  LiquidOrganicNotchView.swift
//  LiquidDynamo
//
//  Organic Liquid Glass Notch content interface:
//  - Hovering over notch reveals connected device icons, clipboard status, and dropper status
//  - No automatic shortcuts or widget panels
//  - Clicking any item smoothly expands liquid around that item to show details
//  - No empty placeholders when devices are disconnected
//  - Hardware sensor & charging ambient indications
//

import AppKit
import Defaults
import SceneKit
import SwiftUI

public enum OrganicNotchExpandedItem: Equatable {
    case none
    case device(String) // deviceKey
    case clipboard
    case dropper
    case storageCleaner
    case colorDropper
    case plexo
    case filedroid
}

public struct LiquidOrganicNotchView: View {
    @ObservedObject var deviceMonitor = DeviceMonitor.shared
    @ObservedObject var clipboardService = ClipboardHistoryService.shared
    @ObservedObject var shelfState = ShelfStateViewModel.shared
    @ObservedObject var sensorMonitor = HardwareSensorMonitor.shared
    @ObservedObject var chargingService = ChargingIntelligenceService.shared
    @ObservedObject var weatherService = AmbientWeatherService.shared
    @ObservedObject var brightnessService = MultiDisplayBrightnessService.shared
    @ObservedObject var memoryRegistry = DeviceMemoryRegistry.shared
    @ObservedObject var safeArea = NotchSafeAreaEngine.shared
    @ObservedObject var island = IslandController.shared
    @ObservedObject var statsService = SystemStatsService.shared
    @ObservedObject var cleaner = StorageCleanupManager.shared
    @ObservedObject var colorDropper = ColorDropperTool.shared
    @ObservedObject var filedroidEngine = FileDroidEngine.shared

    private var activeExpandedItem: OrganicNotchExpandedItem {
        get { island.activeOrganicItem }
        nonmutating set { island.activeOrganicItem = newValue }
    }

    private func toggleExpandedItem(_ item: OrganicNotchExpandedItem) {
        let isSelected = (activeExpandedItem == item)
        let willOpen = !isSelected
        island.cancelHoverCollapse()
        island.isPinnedOpen = willOpen
        if willOpen {
            LiquidViewModel.shared.open(pinned: true)
            AppDelegate.shared?.vm.open(pinned: true)
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            activeExpandedItem = willOpen ? item : .none
        }
    }
    @State private var hoveredDeviceKey: String?
    @State private var hoveredIcon: String?
    @State private var copiedClipboardId: UUID? = nil
    @State private var isDropperTargeted: Bool = false
    @State private var expandedStorageCategory: StorageCleanupCategory? = nil

    public init() {}

    public var body: some View {
        let geom = safeArea.currentGeometry

        VStack(spacing: 0) {
            // Notch Exclusion Zone (Strictly empty, liquid wraps around hardware, centered)
            if geom.isNotched {
                Color.clear
                    .frame(width: geom.rawNotchWidth, height: geom.rawNotchHeight + 8)
            } else {
                Color.clear
                    .frame(height: 16)
            }

            // Liquid Glass Body Content - Centered under the physical notch
            VStack(spacing: 12) {
                // Transient Charging or Hardware Sensor Liquid Indicator (stays above group 1)
                sensorAndChargingBar
                    .frame(maxWidth: .infinity, alignment: .center)

                // 1. Group 1: Connected Devices (Bluetooth, USB, displays, chargers, etc. - Android devices filtered out)
                if !nonAndroidDevices.isEmpty {
                    devicesGroup
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                // 2. Group 2: Quick Tools (Clipboard, Dropper, Purge side by side)
                quickToolsRow
                    .frame(maxWidth: .infinity, alignment: .center)

                // 3. Group 3: Android and Plexo (Plexo chip and ADB device chips)
                if hasAndroidOrPlexoItems {
                    androidRow
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                // 4. Group 4: System Metrics Bar (CPU Temp & RAM Status)
                systemMetricsBar
                    .frame(maxWidth: .infinity, alignment: .center)

                // Detail Expansion (Expands only for the clicked item, centered)
                if activeExpandedItem != .none {
                    expandedDetailView
                        .frame(maxWidth: .infinity, alignment: .center)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                        ))
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .simultaneousGesture(TapGesture().onEnded {
            island.cancelHoverCollapse()
            island.isPinnedOpen = true
            LiquidViewModel.shared.open(pinned: true)
            AppDelegate.shared?.vm.open(pinned: true)
        })
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: activeExpandedItem)
        .onChange(of: deviceMonitor.activeDevices) { _, newDevices in
            for (_, device) in newDevices {
                memoryRegistry.remember(device: device)
            }
        }
        .onAppear {
            statsService.start()
            clipboardService.checkPasteboard()
            deviceMonitor.refreshBluetoothDevices()
            for (_, device) in deviceMonitor.activeDevices {
                memoryRegistry.remember(device: device)
            }
        }
        .onDisappear {
            statsService.stop()
        }
    }

    // MARK: - Sensor & Charging Ambient Bar
    @ViewBuilder
    private var sensorAndChargingBar: some View {
        if chargingService.showTransientChargingRipple {
            HStack(spacing: 6) {
                Image(systemName: chargingService.chargingMethod == .magSafe ? "bolt.shield.fill" : "bolt.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.green)
                Text(chargingService.chargingMethod == .magSafe ? "MagSafe Connected" : "USB-C PD Connected (\(chargingService.adapterWatts)W)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.60))
                    .overlay(Capsule().stroke(Color.green.opacity(0.50), lineWidth: 0.75))
            )
            .transition(.scale.combined(with: .opacity))
        } else if let color = sensorMonitor.activeSensorLiquidColor {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .shadow(color: color.opacity(0.8), radius: 3)
                Text(sensorMonitor.isCameraActive ? "Camera Active" : (sensorMonitor.isScreenRecordingActive ? "Screen Recording Active" : "Microphone Active"))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.60))
                    .overlay(Capsule().stroke(color.opacity(0.55), lineWidth: 0.75))
            )
            .transition(.opacity)
        }
    }

// MARK: - Centered Flow Layout for Wrapping Chips and Device Icons
struct CenteredFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 12
    var verticalSpacing: CGFloat = 8

    struct Row {
        var subviews: [(LayoutSubview, CGSize)]
        var width: CGFloat
        var height: CGFloat
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth: CGFloat
        if let w = proposal.width, w > 0, w != .infinity {
            maxWidth = w
        } else {
            maxWidth = .infinity
        }

        var rows: [Row] = []
        var currentRow: [(LayoutSubview, CGSize)] = []
        var currentLineWidth: CGFloat = 0
        var currentLineHeight: CGFloat = 0

        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if maxWidth != .infinity && size.width > maxWidth {
                size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            }

            let spacing = currentRow.isEmpty ? 0 : horizontalSpacing
            if !currentRow.isEmpty && currentLineWidth + spacing + size.width > maxWidth {
                rows.append(Row(subviews: currentRow, width: currentLineWidth, height: currentLineHeight))
                currentRow = [(subview, size)]
                currentLineWidth = size.width
                currentLineHeight = size.height
            } else {
                currentRow.append((subview, size))
                currentLineWidth += spacing + size.width
                currentLineHeight = max(currentLineHeight, size.height)
            }
        }

        if !currentRow.isEmpty {
            rows.append(Row(subviews: currentRow, width: currentLineWidth, height: currentLineHeight))
        }

        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        if rows.isEmpty { return .zero }
        let totalHeight = rows.map(\.height).reduce(0, +) + CGFloat(rows.count - 1) * verticalSpacing
        let maxRowWidth = rows.map(\.width).max() ?? 0
        return CGSize(width: maxRowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        var y = bounds.minY

        for row in rows {
            let startX = bounds.minX + max(0, (bounds.width - row.width) / 2)
            var x = startX

            for (subview, size) in row.subviews {
                let yOffset = y + (row.height - size.height) / 2
                subview.place(
                    at: CGPoint(x: x, y: yOffset),
                    proposal: ProposedViewSize(width: size.width, height: size.height)
                )
                x += size.width + horizontalSpacing
            }

            y += row.height + verticalSpacing
        }
    }
}

typealias WrappingFlowLayout = CenteredFlowLayout

    // MARK: - Device & Group 3 Filter Helpers
    private var nonAndroidDevices: [DeviceIdentity] {
        if UserDefaults.standard.bool(forKey: "debug_simulate_0_devices") {
            return []
        }
        let simCount = UserDefaults.standard.integer(forKey: "debug_simulate_device_count")
        if simCount > 0 {
            let sampleDevices: [DeviceIdentity] = [
                DeviceIdentity(stableKey: "sim_magsafe", kind: .charger, displayName: "MagSafe 3 Charger", vendor: "Apple", model: "MagSafe", connectionType: .power, capacityBytes: nil, freeSpaceBytes: nil, batteryPercentage: nil, iconName: "bolt.shield.fill", chargerWatts: 140, chargerPort: "MagSafe 3"),
                DeviceIdentity(stableKey: "sim_airpods", kind: .airpods, displayName: "AirPods Pro", vendor: "Apple", model: "AirPods Pro 2", connectionType: .bluetooth, capacityBytes: nil, freeSpaceBytes: nil, batteryPercentage: 95, iconName: "airpodspro", chargerWatts: nil, chargerPort: nil),
                DeviceIdentity(stableKey: "sim_ssd", kind: .ssdDrive, displayName: "Samsung T9 SSD", vendor: "Samsung", model: "T9 2TB", connectionType: .storage, capacityBytes: 2_000_000_000_000, freeSpaceBytes: 1_200_000_000_000, batteryPercentage: nil, iconName: "internaldrive.fill", chargerWatts: nil, chargerPort: nil),
                DeviceIdentity(stableKey: "sim_buds", kind: .headphones, displayName: "realme Buds Wireless", vendor: "realme", model: "Buds", connectionType: .bluetooth, capacityBytes: nil, freeSpaceBytes: nil, batteryPercentage: 70, iconName: "headphones", chargerWatts: nil, chargerPort: nil),
                DeviceIdentity(stableKey: "sim_display", kind: .monitor, displayName: "Studio Display", vendor: "Apple", model: "27-inch 5K", connectionType: .display, capacityBytes: nil, freeSpaceBytes: nil, batteryPercentage: nil, iconName: "display", chargerWatts: nil, chargerPort: nil),
                DeviceIdentity(stableKey: "sim_iphone", kind: .phone, displayName: "iPhone 16 Pro", vendor: "Apple", model: "iPhone 16 Pro", connectionType: .usb, capacityBytes: nil, freeSpaceBytes: nil, batteryPercentage: 88, iconName: "iphone", chargerWatts: nil, chargerPort: nil)
            ]
            return Array(sampleDevices.prefix(simCount))
        }
        return deviceMonitor.sortedActiveDevices.filter { $0.kind != .androidPhone }
    }

    private var androidDevicesFromMonitor: [DeviceIdentity] {
        let allAndroid = deviceMonitor.sortedActiveDevices.filter { $0.kind == .androidPhone }
        if let connectedDev = filedroidEngine.selectedDevice, connectedDev.status == .connected {
            return allAndroid.filter { dev in
                !dev.displayName.localizedCaseInsensitiveContains(connectedDev.displayName) &&
                !connectedDev.displayName.localizedCaseInsensitiveContains(dev.displayName)
            }
        }
        return allAndroid
    }

    private var hasAndroidOrPlexoItems: Bool {
        if UserDefaults.standard.bool(forKey: "debug_hide_group3") {
            return false
        }
        return true
    }

    // MARK: - Group 1: Connected Devices Row (Bluetooth, USB, displays, chargers, etc. - Android devices filtered out)
    @ViewBuilder
    private var devicesGroup: some View {
        if !nonAndroidDevices.isEmpty {
            CenteredFlowLayout(horizontalSpacing: 8, verticalSpacing: 6) {
                ForEach(nonAndroidDevices) { device in
                    deviceIconButton(device: device)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(0.60))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.75)
                    )
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Connected devices")
        }
    }

    // MARK: - Group 2: Quick Tools Row (Clipboard, Dropper, Storage Purge)
    @ViewBuilder
    private var quickToolsRow: some View {
        CenteredFlowLayout(horizontalSpacing: 8, verticalSpacing: 6) {
            clipboardStatusButton
            dropperStatusButton
            storageCleanStatusButton
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick tools")
    }

    // MARK: - Group 3: Android and Plexo Row
    @ViewBuilder
    private var androidRow: some View {
        if hasAndroidOrPlexoItems {
            CenteredFlowLayout(horizontalSpacing: 8, verticalSpacing: 6) {
                plexoStatusButton
                filedroidStatusButton
                ForEach(androidDevicesFromMonitor) { device in
                    deviceIconButton(device: device)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Android and Plexo")
        }
    }

    // MARK: - Group 4: System Metrics Bar (CPU Temp & RAM Status)
    @ViewBuilder
    private var systemMetricsBar: some View {
        HStack(spacing: 12) {
            // CPU Temperature
            HStack(spacing: 5) {
                Image(systemName: statsService.thermalStateIcon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(statsService.isTemperatureAvailable ? statsService.thermalStateColor : .secondary)

                Text("CPU:")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Text(statsService.formattedCPUTemperature)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(statsService.isTemperatureAvailable ? .white : .secondary.opacity(0.8))
            }

            // Divider dot
            Circle()
                .fill(Color.white.opacity(0.20))
                .frame(width: 3, height: 3)

            // RAM Status
            HStack(spacing: 5) {
                Image(systemName: "memorychip")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(statsService.memoryPercentage > 85 ? Color.orange : Color.cyan)

                Text("RAM:")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Text("\(statsService.formattedMemoryUsed) / \(statsService.formattedMemoryTotal) (\(Int(round(statsService.memoryPercentage)))%)")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.45))
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.6))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("System status")
    }

    // MARK: - Device Icon Button
    @ViewBuilder
    private func deviceIconButton(device: DeviceIdentity) -> some View {
        let isSelected = activeExpandedItem == .device(device.stableKey)
        Button {
            if device.kind == .androidPhone {
                FileDroidWindowController.shared.showWindow()
            }
            toggleExpandedItem(.device(device.stableKey))
        } label: {
            HStack(spacing: 8) {
                // Device Icon / 3D model icon
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.12))
                        .frame(width: 26, height: 26)
                        .overlay(
                            Circle()
                                .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.22), lineWidth: isSelected ? 1.5 : 0.75)
                        )

                    if let preview = DeviceModelResolver.shared.findPreviewImage(for: device.kind) {
                        Image(nsImage: preview)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 18)
                    } else if device.kind == .androidPhone {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(red: 0.24, green: 0.86, blue: 0.52))
                    } else if device.kind == .charger {
                        Image(systemName: device.iconName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.green)
                    } else if device.kind == .earbuds || device.kind == .airpods {
                        Image(systemName: "airpodspro")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white)
                    } else if device.kind == .neckband || device.kind == .headphones || device.kind == .earphones {
                        Image(systemName: "headphones")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white)
                    } else if device.kind == .ssdDrive || device.kind == .usbStick {
                        Image(systemName: "internaldrive.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.cyan)
                    } else if device.kind == .monitor {
                        Image(systemName: "display")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.blue)
                    } else {
                        Image(systemName: device.iconName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.95))
                    }
                }

                // Device Name & Status
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(maxWidth: 120, alignment: .leading)

                    if device.kind == .charger {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 4.5, height: 4.5)
                            if let watts = device.chargerWatts, watts > 0 {
                                Text("\(watts)W")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.green)
                            }
                            if let port = device.chargerPort {
                                Text(port.contains("MagSafe") ? "MagSafe" : "USB-C")
                                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if device.kind == .monitor {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 4.5, height: 4.5)
                            let isMain = device.model.contains("Main") || device.displayName.contains("Built-in")
                            Text(isMain ? "Main Display" : "Connected Display")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.blue)

                            let matchingDisp = brightnessService.displays.first(where: { "display_\($0.id)" == device.stableKey })
                            if let disp = matchingDisp {
                                Text("\(Int(disp.brightness * 100))%")
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.85))
                            } else if let res = device.scaledResolution ?? device.resolution {
                                Text(res)
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        HStack(spacing: 5) {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 4.5, height: 4.5)
                                Text("Connected")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color.green)
                            }

                            if let bat = device.batteryPercentage {
                                Text("\(bat)%")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(bat <= 20 ? Color.red : Color.green)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.06))
                    .overlay(Capsule().stroke(isSelected ? Color.accentColor : Color.white.opacity(0.12), lineWidth: isSelected ? 1.5 : 0.5))
            )
        }
        .buttonStyle(.plain)
        .help(device.displayName)
    }

    // MARK: - Clipboard Status Button
    @ViewBuilder
    private var clipboardStatusButton: some View {
        let isSelected = activeExpandedItem == .clipboard
        Button {
            toggleExpandedItem(.clipboard)
        } label: {
            HStack(spacing: 6) {
                if let latest = clipboardService.recentEntries.first {
                    Image(systemName: latest.iconSymbolName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(latest.iconColor)

                    Text(latest.previewText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .frame(maxWidth: 110)
                } else {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.cyan)

                    Text("Clipboard")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.cyan.opacity(0.35) : Color.black.opacity(0.60))
                    .overlay(Capsule().stroke(isSelected ? Color.cyan : Color.white.opacity(0.18), lineWidth: isSelected ? 1.5 : 0.75))
            )
        }
        .buttonStyle(.plain)
        .help("Clipboard History")
    }

    // MARK: - Dropper Status Button
    @ViewBuilder
    private var dropperStatusButton: some View {
        let isSelected = activeExpandedItem == .dropper
        let countStr = "\(shelfState.items.count)"
        let labelText = shelfState.items.isEmpty ? "Dropper" : countStr
        let textColor = shelfState.items.isEmpty ? Color.secondary : Color.white

        Button {
            toggleExpandedItem(.dropper)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.orange)

                Text(labelText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(textColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.orange.opacity(0.35) : Color.black.opacity(0.60))
                    .overlay(Capsule().stroke(isSelected ? Color.orange : Color.white.opacity(0.18), lineWidth: isSelected ? 1.5 : 0.75))
            )
        }
        .buttonStyle(.plain)
        .help("Temporary Dropper Shelf")
    }

    // MARK: - Storage Clean / Purge Status Button
    @ViewBuilder
    private var storageCleanStatusButton: some View {
        let isSelected = activeExpandedItem == .storageCleaner
        let reclaimable = cleaner.latestResult?.totalReclaimableBytes ?? 0
        let labelText: String = {
            if cleaner.isScanning {
                return "Scanning…"
            } else if cleaner.isCleaning {
                return "Cleaning…"
            } else if reclaimable > 0 {
                return "Purge: \(cleaner.latestResult?.formattedTotalReclaimable ?? "")"
            } else {
                return "Clean"
            }
        }()

        Button {
            toggleExpandedItem(.storageCleaner)
        } label: {
            HStack(spacing: 6) {
                if cleaner.isScanning || cleaner.isCleaning {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Color.mint)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(reclaimable > 0 ? Color.mint : Color.secondary)
                }

                Text(labelText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(reclaimable > 0 ? .white : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.mint.opacity(0.35) : Color.black.opacity(0.60))
                    .overlay(
                        Capsule()
                            .stroke(isSelected ? Color.mint : (reclaimable > 0 ? Color.mint.opacity(0.40) : Color.white.opacity(0.18)), lineWidth: isSelected ? 1.5 : 0.75)
                    )
            )
        }
        .buttonStyle(.plain)
        .help("Storage Purge — Click to inspect and clean storage")
    }

    // MARK: - Color Dropper Status Button
    @ViewBuilder
    private var colorDropperStatusButton: some View {
        let isSelected = activeExpandedItem == .colorDropper
        let tool = ColorDropperTool.shared
        let swatchColor = tool.currentColor?.swiftUIColor ?? Color.accentColor

        Button {
            toggleExpandedItem(.colorDropper)
        } label: {
            HStack(spacing: 6) {
                if tool.isSampling {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Color.purple)
                    Text("Picking…")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                } else {
                    Circle()
                        .fill(swatchColor)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 0.75))

                    Image(systemName: "eyedropper.halffull")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.purple)

                    if let hex = tool.currentColor?.hex {
                        Text(hex)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.95))
                    } else {
                        Text("Color")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.purple.opacity(0.35) : Color.black.opacity(0.60))
                    .overlay(Capsule().stroke(isSelected ? Color.purple : Color.white.opacity(0.18), lineWidth: isSelected ? 1.5 : 0.75))
            )
        }
        .buttonStyle(.plain)
        .help("Color Dropper & Screen Eyedropper")
    }

    // MARK: - Plexo Multi-Network Downloader Status Button
    @ViewBuilder
    private var plexoStatusButton: some View {
        let isSelected = activeExpandedItem == .plexo
        let activeCount = PlexoDownloadEngine.shared.activeTasks.filter { $0.state == .downloading }.count

        Button {
            toggleExpandedItem(.plexo)
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 12, height: 12)
                    Image(systemName: "bolt.horizontal.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                }

                if activeCount > 0 {
                    Text("\(activeCount) Turbo")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.cyan)
                    Text(PlexoFormatting.formatSpeed(PlexoNetworkManager.shared.totalDownloadSpeed))
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                } else {
                    Text("Plexo")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.cyan.opacity(0.35) : Color.black.opacity(0.60))
                    .overlay(Capsule().stroke(isSelected ? Color.cyan : Color.white.opacity(0.18), lineWidth: isSelected ? 1.5 : 0.75))
            )
        }
        .buttonStyle(.plain)
        .help("Plexo Multi-Network Download Accelerator")
    }

    // MARK: - FileDroid & OpenMTP Status Button
    @ViewBuilder
    private var filedroidStatusButton: some View {
        let isSelected = activeExpandedItem == .filedroid
        let connectedDev = filedroidEngine.selectedDevice
        let hasDevice = (connectedDev?.status == .connected)

        Button {
            FileDroidWindowController.shared.showWindow()
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.green, Color.teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 12, height: 12)
                    Image(systemName: "phone.fill")
                        .font(.system(size: 6.5, weight: .bold))
                        .foregroundStyle(.white)
                }

                if let dev = connectedDev, dev.status == .connected {
                    Text(dev.displayName)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.green)
                        .lineLimit(1)
                    if dev.internalStorageFree > 0 {
                        Text(FileDroidFormatting.formatBytes(dev.internalStorageFree) + " free")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                } else {
                    Text("FileDroid")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.green.opacity(0.35) : Color.black.opacity(0.60))
                    .overlay(Capsule().stroke(isSelected ? Color.green : (hasDevice ? Color.green.opacity(0.5) : Color.white.opacity(0.18)), lineWidth: isSelected ? 1.5 : 0.75))
            )
        }
        .buttonStyle(.plain)
        .help(hasDevice ? "FileDroid — \(connectedDev?.displayName ?? "") mounted in Finder" : "FileDroid & OpenMTP Android Storage Bridge")
    }

    // MARK: - Expanded Detail View
    @ViewBuilder
    private var expandedDetailView: some View {
        switch activeExpandedItem {
        case .none:
            EmptyView()

        case .device(let key):
            if let device = deviceMonitor.activeDevices[key] {
                deviceDetailCard(device: device)
            } else if let remembered = memoryRegistry.entries[key] {
                rememberedDeviceDetailCard(entry: remembered)
            } else {
                fallbackDeviceDetailCard(key: key)
            }

        case .clipboard:
            clipboardDetailCard

        case .dropper:
            dropperDetailCard

        case .storageCleaner:
            storageCleanDetailCard

        case .colorDropper:
            colorDropperDetailCard

        case .plexo:
            PlexoView()

        case .filedroid:
            FileDroidView()
        }
    }

    // MARK: - Remembered & Fallback Device Cards
    @ViewBuilder
    private func rememberedDeviceDetailCard(entry: DeviceMemoryEntry) -> some View {
        let kind = DeviceKind(rawValue: entry.kind) ?? .generic
        let rememberedDev = DeviceIdentity(
            stableKey: entry.stableKey,
            kind: kind,
            displayName: entry.displayName,
            vendor: "Saved Device",
            model: entry.preferredVisualAsset ?? kind.rawValue,
            connectionType: .bluetooth,
            batteryPercentage: nil,
            iconName: kind.defaultIconName
        )
        deviceDetailCard(device: rememberedDev)
    }

    @ViewBuilder
    private func fallbackDeviceDetailCard(key: String) -> some View {
        let fallbackDev = DeviceIdentity(
            stableKey: key,
            kind: .generic,
            displayName: "Connected Device",
            vendor: "External",
            model: "Generic Device",
            connectionType: .usb,
            batteryPercentage: nil,
            iconName: "cable.connector"
        )
        deviceDetailCard(device: fallbackDev)
    }

    // MARK: - Device Detail Card (with 3D Asset & Controls)
    @ViewBuilder
    private func deviceDetailCard(device: DeviceIdentity) -> some View {
        HStack(spacing: 12) {
            // Interactive 3D Model Asset (Compact proportionate size)
            DeviceInteractive3DView(device: device, size: 40, rpm: 18)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.40))
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.75))
                )

            // Device Context Information
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(device.displayName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    let isConnected = deviceMonitor.activeDevices[device.stableKey] != nil
                    if !isConnected {
                        Text("Not connected")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                            .foregroundStyle(.secondary)
                    }

                    Text(device.kind.rawValue)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                        .foregroundStyle(.secondary)
                }

                // Specific Details Per Device Category
                if device.kind == .charger {
                    chargerInfoRow(device: device)
                } else if device.kind == .earbuds || device.kind == .airpods || device.kind == .earphones || device.kind == .headphones || device.kind == .neckband {
                    airPodsBatteryRow(device: device)
                } else if device.kind == .androidPhone {
                    androidInfoRow(device: device)
                } else if device.kind == .ssdDrive || device.kind == .usbStick {
                    storageInfoRow(device: device)
                } else if device.kind == .monitor {
                    monitorInfoRow(device: device)
                } else {
                    genericDeviceInfoRow(device: device)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.65))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 0.75))
        )
    }

    // MARK: - Charger Info Row
    @ViewBuilder
    private func chargerInfoRow(device: DeviceIdentity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Port row with cable connector icon and wattage badge
            HStack(spacing: 6) {
                Image(systemName: "cable.connector.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.green)

                Text(device.chargerPort ?? "USB-C Port")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                if let watts = device.chargerWatts, watts > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                        Text("\(watts)W")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule()
                            .fill(Color.green.opacity(0.20))
                            .overlay(Capsule().stroke(Color.green.opacity(0.40), lineWidth: 0.75))
                    )
                    .foregroundStyle(Color.green)
                }
            }

            // Power draw & Electrical Telemetry (Voltage & Current)
            HStack(spacing: 8) {
                if let v = device.chargingVoltage, let a = device.chargingCurrent, v > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1fV • %.2fA", v, a))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                if let actualPower = device.chargingPowerWatts, actualPower > 0 {
                    Text(String(format: "• %.1fW draw", actualPower))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.green.opacity(0.9))
                }
            }

            // Battery state & charging status description
            HStack(spacing: 6) {
                if let bat = device.batteryPercentage {
                    HStack(spacing: 3) {
                        Image(systemName: "battery.100.bolt")
                            .font(.system(size: 10))
                        Text("\(bat)%")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(Color.green)
                }

                if let status = device.chargingStatusDescription {
                    Text(status)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - AirPods Battery Row
    @ViewBuilder
    private func airPodsBatteryRow(device: DeviceIdentity) -> some View {
        HStack(spacing: 12) {
            if let l = device.leftBattery {
                HStack(spacing: 3) {
                    Image(systemName: "earbuds.left")
                        .font(.system(size: 10))
                    Text("\(l)%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(l <= 20 ? Color.red : Color.green)
            }
            if let r = device.rightBattery {
                HStack(spacing: 3) {
                    Image(systemName: "earbuds.right")
                        .font(.system(size: 10))
                    Text("\(r)%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(r <= 20 ? Color.red : Color.green)
            }
            if let c = device.caseBattery {
                HStack(spacing: 3) {
                    Image(systemName: "battery.100")
                        .font(.system(size: 10))
                    Text("Case \(c)%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(c <= 20 ? Color.red : Color.green)
            }
            if device.leftBattery == nil && device.rightBattery == nil && device.caseBattery == nil, let bat = device.batteryPercentage {
                HStack(spacing: 4) {
                    Image(systemName: "battery.100")
                        .font(.system(size: 10))
                    Text("\(bat)%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(bat <= 20 ? Color.red : Color.green)
            }
        }
    }

    // MARK: - Android Info Row
    @ViewBuilder
    private func androidInfoRow(device: DeviceIdentity) -> some View {
        let fdDev = filedroidEngine.selectedDevice
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                if let battery = fdDev?.batteryLevel ?? device.batteryPercentage {
                    HStack(spacing: 4) {
                        Image(systemName: (fdDev?.isCharging == true) ? "bolt.fill" : "battery.100")
                            .font(.system(size: 10))
                        Text("\(battery)%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(battery <= 20 ? Color.red : Color.green)
                }

                Text(fdDev?.androidVersion ?? device.connectionType.rawValue)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                let adbClient = LiveADBClient.shared
                let adbPath = adbClient.adbPath
                let hasAdb = adbPath != nil && !adbPath!.isEmpty
                let targetSerial = fdDev?.serial ?? device.stableKey

                Button {
                    if hasAdb {
                        AndroidFileManagerWindowManager.shared.openWindow(
                            for: targetSerial,
                            deviceName: device.displayName,
                            deviceModel: fdDev?.model ?? device.model,
                            client: adbClient
                        )
                    } else {
                        SettingsWindowController.shared.showWindow()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.gearshape")
                            .font(.system(size: 9, weight: .bold))
                        Text(hasAdb ? "Open in app" : "Set adb path…")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(hasAdb ? Color.green.opacity(0.35) : Color.orange.opacity(0.35))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke((hasAdb ? Color.green : Color.orange).opacity(0.6), lineWidth: 0.75))
                }
                .buttonStyle(.plain)
                .help(hasAdb ? "Open in-app Android File Manager for \(device.displayName)" : "ADB binary not found. Click to configure ADB path in Settings.")
            }

            if let total = fdDev?.internalStorageTotal, total > 0, let free = fdDev?.internalStorageFree {
                let used = fdDev?.internalStorageUsed ?? (total > free ? total - free : 0)
                let pct = Double(used) / Double(total)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(Color.green)
                            .frame(width: geo.size.width * CGFloat(pct))
                    }
                }
                .frame(height: 4)

                HStack {
                    Text("\(FileDroidFormatting.formatBytes(free)) free of \(FileDroidFormatting.formatBytes(total))")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
    }

    // MARK: - Storage Info Row
    @ViewBuilder
    private func storageInfoRow(device: DeviceIdentity) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let total = device.capacityBytes, let free = device.freeSpaceBytes {
                let used = total > free ? total - free : 0
                let pct = total > 0 ? Double(used) / Double(total) : 0
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(Color.cyan)
                            .frame(width: geo.size.width * CGFloat(pct))
                    }
                }
                .frame(height: 5)

                HStack {
                    Text("\(formatBytes(free)) free of \(formatBytes(total))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let mount = device.mountPath {
                        Button {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: mount)
                        } label: {
                            Text("Open in Finder")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.cyan)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Monitor Info Row & Brightness Controls
    @ViewBuilder
    private func monitorInfoRow(device: DeviceIdentity) -> some View {
        let targetDisplay: ManagedDisplay? = {
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
        }()

        VStack(alignment: .leading, spacing: 6) {
            // Resolution, Refresh Rate & Control Method Badge
            HStack(spacing: 6) {
                if let res = device.resolution {
                    Text("\(res) • \(String(format: "%.0fHz", device.refreshRate ?? 60.0))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let disp = targetDisplay {
                    Text(disp.isBuiltIn ? "Built-in" : disp.controlMethod.rawValue)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.blue.opacity(0.18)))
                        .foregroundStyle(Color.blue)
                }
            }

            // Live Brightness Slider
            if let disp = targetDisplay {
                HStack(spacing: 8) {
                    Image(systemName: "sun.min.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    Slider(value: Binding(
                        get: { Double(disp.brightness) },
                        set: { brightnessService.setBrightness(Float($0), for: disp) }
                    ), in: 0...1)
                    .accentColor(disp.isBuiltIn ? .blue : (disp.controlMethod == .softwareDimming ? .orange : .cyan))

                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Text("\(Int(disp.brightness * 100))%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .frame(width: 34, alignment: .trailing)
                }

                // Quick Brightness Presets & macOS Display Settings Button
                HStack(spacing: 6) {
                    ForEach([0.25, 0.50, 0.75, 1.0], id: \.self) { preset in
                        Button {
                            brightnessService.setBrightness(Float(preset), for: disp)
                        } label: {
                            Text("\(Int(preset * 100))%")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(
                                    Capsule()
                                        .fill(abs(Double(disp.brightness) - preset) < 0.05 ? Color.blue.opacity(0.35) : Color.white.opacity(0.08))
                                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                                )
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Button {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 9))
                            Text("Displays")
                                .font(.system(size: 9.5, weight: .medium))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open macOS Displays Settings")
                }
            }
        }
    }

    // MARK: - Generic Device Info Row
    @ViewBuilder
    private func genericDeviceInfoRow(device: DeviceIdentity) -> some View {
        let isActive = deviceMonitor.activeDevices[device.stableKey] != nil
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Circle().fill(isActive ? Color.green : Color.secondary).frame(width: 5, height: 5)
                Text(isActive ? "Connected" : "Not connected")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isActive ? Color.green : Color.secondary)
            }

            if let battery = device.batteryPercentage {
                HStack(spacing: 4) {
                    Image(systemName: "battery.100")
                        .font(.system(size: 10))
                    Text("\(battery)%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(battery <= 20 ? Color.red : Color.green)
            }
            Text(device.kind.rawValue)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Clipboard Detail Card
    @ViewBuilder
    private var clipboardDetailCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Clipboard History")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                if !clipboardService.recentEntries.isEmpty {
                    Button("Clear") {
                        clipboardService.clearHistory()
                    }
                    .font(.system(size: 10, weight: .bold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            if clipboardService.recentEntries.isEmpty && clipboardService.pinnedEntries.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text("Clipboard Empty")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 10)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(clipboardService.pinnedEntries) { entry in
                            clipboardRow(entry: entry, isPinned: true)
                        }
                        ForEach(clipboardService.recentEntries.prefix(25)) { entry in
                            clipboardRow(entry: entry, isPinned: false)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.65))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.18), lineWidth: 0.75))
        )
    }

    @ViewBuilder
    private func clipboardRow(entry: ClipboardEntry, isPinned: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                clipboardService.copyToPasteboard(entry)
                copiedClipboardId = entry.id
                Task {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    if copiedClipboardId == entry.id {
                        copiedClipboardId = nil
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if copiedClipboardId == entry.id {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.green)
                    } else if entry.type == .image, let data = entry.imageData, let img = NSImage(data: data) {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 18, height: 18)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Image(systemName: entry.iconSymbolName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(entry.iconColor)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.previewText)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.95))
                            .lineLimit(1)

                        Text(copiedClipboardId == entry.id ? "Copied to clipboard!" : entry.detailText)
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(copiedClipboardId == entry.id ? Color.green : Color.secondary.opacity(0.8))
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Button {
                clipboardService.togglePin(entry)
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10))
                    .foregroundStyle(isPinned ? Color.orange : Color.secondary)
            }
            .buttonStyle(.plain)

            Button {
                clipboardService.remove(entry)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(copiedClipboardId == entry.id ? Color.green.opacity(0.12) : Color.white.opacity(0.03))
        )
    }

    // MARK: - Dropper Detail Card
    @ViewBuilder
    private var dropperDetailCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Dropper Shelf")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                if !shelfState.items.isEmpty {
                    Button("Clear All") {
                        shelfState.clearAll()
                    }
                    .font(.system(size: 10, weight: .bold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            if shelfState.items.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text("Dropper Empty")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(shelfState.items) { item in
                            ShelfItemView(item: item)
                                .frame(width: 95)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isDropperTargeted ? Color.orange.opacity(0.25) : Color.black.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isDropperTargeted ? Color.orange : Color.white.opacity(0.18), lineWidth: isDropperTargeted ? 1.5 : 0.75)
                )
        )
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $isDropperTargeted) { providers in
            ShelfStateViewModel.shared.load(providers)
            return true
        }
    }

    // MARK: - Storage Clean Detail Card (Purge Dropdown)
    @ViewBuilder
    private var storageCleanDetailCard: some View {
        let res = cleaner.latestResult
        let reclaimable = res?.totalReclaimableBytes ?? 0
        let reclaimableStr = res?.formattedTotalReclaimable ?? (cleaner.isScanning ? "Scanning…" : "0 B")
        let categories = res?.categoriesWithReclaimableItems ?? []

        VStack(alignment: .leading, spacing: 10) {
            // Header: Hero Reclaimable Metric & Action Buttons
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(colors: [Color.green.opacity(0.4), Color.mint.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 30, height: 30)
                            .overlay(Circle().stroke(Color.mint.opacity(0.6), lineWidth: 1))

                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.mint)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(reclaimableStr)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(colors: [Color.white, Color.mint], startPoint: .leading, endPoint: .trailing)
                                )
                            Text("Cleanable")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                        }

                        Text(cleaner.isScanning ? "Analyzing storage categories…" : (reclaimable > 0 ? "\(categories.count) categories with safe-to-trash files" : "Your Mac storage is tidy and optimized"))
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    // Rescan button
                    Button {
                        cleaner.scanAgain()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 26, height: 26)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.10))
                                    .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.6))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Scan Again")
                    .disabled(cleaner.isScanning || cleaner.isCleaning)

                    // One-Click Clean All Button
                    if reclaimable > 0 {
                        Button {
                            Task {
                                await cleaner.cleanAll()
                            }
                        } label: {
                            HStack(spacing: 5) {
                                if cleaner.isCleaning {
                                    ProgressView()
                                        .controlSize(.mini)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 10, weight: .bold))
                                }

                                Text(cleaner.isCleaning ? "Cleaning…" : "Purge All")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(colors: [Color.green, Color.mint], startPoint: .leading, endPoint: .trailing)
                                    )
                                    .shadow(color: Color.green.opacity(0.35), radius: 5)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(cleaner.isCleaning)
                    }
                }
            }

            // Disk Visual Gauge Bar
            if let result = res {
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        let w = geo.size.width
                        let usedFrac = CGFloat(result.usedPercentage)
                        let recFrac = CGFloat(result.reclaimablePercentage)
                        let freeFrac = CGFloat(result.freePercentage)

                        HStack(spacing: 2) {
                            // Non-reclaimable Used Space
                            RoundedRectangle(cornerRadius: 3)
                                .fill(LinearGradient(colors: [Color.blue.opacity(0.8), Color.indigo.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(4, w * max(0, usedFrac - recFrac)))

                            // Reclaimable / Cleanable Space
                            if recFrac > 0.001 {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(LinearGradient(colors: [Color.green, Color.mint], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(6, w * recFrac))
                            }

                            // Free Disk Space
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.12))
                                .frame(width: max(4, w * freeFrac))
                        }
                    }
                    .frame(height: 7)

                    HStack {
                        HStack(spacing: 3) {
                            Circle().fill(Color.blue).frame(width: 5, height: 5)
                            Text("Used: \(result.formattedVolumeUsed)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 3) {
                            Circle().fill(Color.mint).frame(width: 5, height: 5)
                            Text("Cleanable: \(result.formattedTotalReclaimable)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.mint)
                        }

                        Spacer()

                        HStack(spacing: 3) {
                            Circle().fill(Color.white.opacity(0.3)).frame(width: 5, height: 5)
                            Text("Free: \(result.formattedVolumeFree)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // Category Breakdown Accordion Dropdowns
            if categories.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                        .font(.system(size: 12))
                    Text("No junk files found. Your storage is clean!")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 10)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(categories) { cat in
                            storageCategoryDropdownRow(for: cat, in: res)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 180)
            }

            // Footer: Safety Guarantee & Full Settings Button
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.green)
                    Text("Moved to Trash safely • System daemons protected")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    SettingsWindowController.shared.showWindow()
                } label: {
                    HStack(spacing: 3) {
                        Text("Full Cleaner")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(Color.mint.opacity(0.9))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.70))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [Color.mint.opacity(0.40), Color.white.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                )
        )
    }

    // MARK: - Category Dropdown Row
    @ViewBuilder
    private func storageCategoryDropdownRow(for category: StorageCleanupCategory, in result: StorageCleanupResult?) -> some View {
        let isExpanded = expandedStorageCategory == category
        let items = result?.itemsByCategory[category] ?? []
        let catTotalStr = result?.formattedTotal(for: category) ?? "0 B"

        VStack(spacing: 0) {
            // Header Row
            HStack(spacing: 8) {
                // Category Icon
                Image(systemName: category.iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(category.color)
                    .frame(width: 16)

                // Category Name & Item count
                Text(category.rawValue)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("(\(items.count))")
                    .font(.system(size: 9.5, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                // Reclaimable Size Badge
                Text(catTotalStr)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(category.color)

                // Individual Category Clean Button
                Button {
                    Task {
                        await cleaner.cleanCategory(category)
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(4)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Clean \(category.rawValue)")

                // Dropdown Toggle Chevron
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        expandedStorageCategory = isExpanded ? nil : category
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isExpanded ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
            )

            // Unfolded Dropdown Content (Files/Folders list)
            if isExpanded {
                VStack(spacing: 3) {
                    ForEach(items.prefix(8)) { item in
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name)
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(1)

                                if let detail = item.detail {
                                    Text(detail)
                                        .font(.system(size: 8.5, design: .rounded))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Text(item.formattedSize)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)

                            // Finder Reveal
                            Button {
                                cleaner.revealInFinder(path: item.path)
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Reveal in Finder")

                            // Delete single item
                            Button {
                                Task {
                                    await cleaner.cleanItems([item])
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8))
                                    .foregroundStyle(Color.red.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .help("Move to Trash")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.black.opacity(0.35))
                        )
                    }

                    if items.count > 8 {
                        Text("+ \(items.count - 8) more items in \(category.rawValue)")
                            .font(.system(size: 8.5, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
                .padding(.top, 4)
                .padding(.leading, 12)
            }
        }
    }

    // MARK: - Color Dropper Detail Card
    @ViewBuilder
    private var colorDropperDetailCard: some View {
        let tool = ColorDropperTool.shared
        let current = tool.currentColor ?? PickedColorRecord(hex: "#007AFF", red: 0.0, green: 0.478, blue: 1.0)

        VStack(spacing: 12) {
            // Header: Title + Screen Sampler Trigger Button
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "eyedropper.halffull")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.purple)
                    Text("Color Dropper")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                }

                Spacer()

                Button {
                    island.isPinnedOpen = true
                    tool.sampleColor()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 11, weight: .bold))
                        Text(tool.isSampling ? "Sampling…" : "Pick from Screen")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.purple.opacity(0.85))
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(tool.isSampling)
            }

            // Main Swatch & Value Chips
            HStack(spacing: 14) {
                // Large Color Swatch
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(current.swiftUIColor)
                        .frame(width: 76, height: 76)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                        .shadow(color: current.swiftUIColor.opacity(0.4), radius: 8, x: 0, y: 3)

                    Image(systemName: "eyedropper")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(current.isLight ? Color.black.opacity(0.7) : Color.white.opacity(0.9))
                }

                // Format Cards (HEX, RGB, HSL) with click-to-copy
                VStack(spacing: 6) {
                    colorFormatRow(label: "HEX", value: current.hex)
                    colorFormatRow(label: "RGB", value: current.rgbString)
                    colorFormatRow(label: "HSL", value: current.hslString)
                }
            }

            // Recent Swatches Row
            if !tool.recentColors.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("RECENT COLORS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.secondary)

                        Spacer()

                        Button {
                            tool.clearRecent()
                        } label: {
                            Text("Clear")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.secondary.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(tool.recentColors) { record in
                                Button {
                                    tool.selectRecent(record)
                                } label: {
                                    Circle()
                                        .fill(record.swiftUIColor)
                                        .frame(width: 22, height: 22)
                                        .overlay(
                                            Circle()
                                                .stroke(record.hex == current.hex ? Color.white : Color.white.opacity(0.2), lineWidth: record.hex == current.hex ? 2 : 0.75)
                                        )
                                        .shadow(color: record.swiftUIColor.opacity(0.3), radius: 3, x: 0, y: 1)
                                }
                                .buttonStyle(.plain)
                                .help(record.hex)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.70))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.75)
                )
        )
    }

    @ViewBuilder
    private func colorFormatRow(label: String, value: String) -> some View {
        let isCopied = ColorDropperTool.shared.copiedFormatFeedback == label

        Button {
            ColorDropperTool.shared.copyFormat(value, formatName: label)
        } label: {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 30, alignment: .leading)

                Text(value)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)

                Spacer()

                if isCopied {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("Copied")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(Color.green)
                    .transition(.opacity)
                } else {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isCopied ? Color.green.opacity(0.15) : Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isCopied ? Color.green.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
