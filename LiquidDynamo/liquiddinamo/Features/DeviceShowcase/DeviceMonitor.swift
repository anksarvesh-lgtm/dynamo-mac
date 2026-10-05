//
//  DeviceMonitor.swift
//  boringNotch
//
//  Created for Boring Notch
//

import AppKit
import Combine
import Defaults
import DiskArbitration
import Foundation
import IOBluetooth
import IOKit
import IOKit.usb
import SwiftUI

// MARK: - Device Models

public enum DeviceKind: String, Codable, CaseIterable, Identifiable {
    case earbuds = "Earbuds"
    case headphones = "Headphones"
    case speaker = "Speaker"
    case ssdDrive = "SSD / Drive"
    case usbStick = "USB Flash Drive"
    case mouse = "Mouse"
    case keyboard = "Keyboard"
    case phone = "Phone"
    case generic = "Generic"

    public var id: String { rawValue }

    public var defaultIconName: String {
        switch self {
        case .earbuds: return "airpodspro"
        case .headphones: return "headphones"
        case .speaker: return "speaker.wave.2.fill"
        case .ssdDrive: return "internaldrive"
        case .usbStick: return "externaldrive.fill"
        case .mouse: return "computermouse.fill"
        case .keyboard: return "keyboard"
        case .phone: return "iphone"
        case .generic: return "cable.connector"
        }
    }
}

public enum ConnectionType: String, Codable, CaseIterable {
    case bluetooth = "Bluetooth"
    case storage = "Storage"
    case usb = "USB"
}

public struct DeviceIdentity: Identifiable, Equatable, Hashable {
    public var id: String { stableKey }
    public let stableKey: String
    public let kind: DeviceKind
    public let displayName: String
    public let vendor: String
    public let model: String
    public let connectionType: ConnectionType
    public let capacityBytes: UInt64?
    public let freeSpaceBytes: UInt64?
    public let mountPath: String?
    public let batteryPercentage: Int?
    public let iconName: String

    public init(
        stableKey: String,
        kind: DeviceKind,
        displayName: String,
        vendor: String,
        model: String,
        connectionType: ConnectionType,
        capacityBytes: UInt64? = nil,
        freeSpaceBytes: UInt64? = nil,
        mountPath: String? = nil,
        batteryPercentage: Int? = nil,
        iconName: String? = nil
    ) {
        self.stableKey = stableKey
        self.kind = kind
        self.displayName = displayName
        self.vendor = vendor
        self.model = model
        self.connectionType = connectionType
        self.capacityBytes = capacityBytes
        self.freeSpaceBytes = freeSpaceBytes
        self.mountPath = mountPath
        self.batteryPercentage = batteryPercentage
        self.iconName = iconName ?? kind.defaultIconName
    }

    public var formattedCapacity: String? {
        guard let bytes = capacityBytes, bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    public var formattedFreeSpace: String? {
        guard let bytes = freeSpaceBytes, bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    @discardableResult
    public func eject() -> Bool {
        guard let mountPath = mountPath else { return false }
        let url = URL(fileURLWithPath: mountPath)
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: url)
            return true
        } catch {
            return false
        }
    }
}

public enum DeviceEventType: String, Codable {
    case connected = "Connected"
    case disconnected = "Disconnected"
}

public struct DeviceEvent: Identifiable, Equatable {
    public let id = UUID()
    public let type: DeviceEventType
    public let device: DeviceIdentity
    public let timestamp: Date

    public init(type: DeviceEventType, device: DeviceIdentity, timestamp: Date = Date()) {
        self.type = type
        self.device = device
        self.timestamp = timestamp
    }
}

// MARK: - Device Monitor Service

@MainActor
public final class DeviceMonitor: ObservableObject {
    public static let shared = DeviceMonitor()

    @Published public private(set) var activeDevices: [String: DeviceIdentity] = [:]
    @Published public private(set) var recentEvents: [DeviceEvent] = []
    @Published public private(set) var latestEvent: DeviceEvent?

    public let eventSubject = PassthroughSubject<DeviceEvent, Never>()

    // Storage monitoring
    private var daSession: DASession?
    private var storageMountDebounceWorkItems: [String: DispatchWorkItem] = [:]
    private var mountedVolumeKeys: [URL: String] = [:] // Map mount URL -> stableKey

    // USB monitoring
    private var notifyPort: IONotificationPortRef?
    private var runLoopSource: CFRunLoopSource?
    private var usbAddedIterators: [io_iterator_t] = []
    private var usbRemovedIterators: [io_iterator_t] = []
    private var activeUSBRegistryIDs: [UInt64: String] = [:] // Map IOKit registryID -> stableKey

    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupBluetoothMonitoring()
        setupStorageMonitoring()
        setupUSBMonitoring()
    }

    deinit {
        // Clean up IOKit notification port
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        for iter in usbAddedIterators { IOObjectRelease(iter) }
        for iter in usbRemovedIterators { IOObjectRelease(iter) }
        if let notifyPort = notifyPort {
            IONotificationPortDestroy(notifyPort)
        }
    }

    // MARK: - Public Publishing Helper

    private func publishEvent(type: DeviceEventType, device: DeviceIdentity) {
        let event = DeviceEvent(type: type, device: device)
        latestEvent = event
        recentEvents.insert(event, at: 0)
        if recentEvents.count > 50 {
            recentEvents.removeLast(recentEvents.count - 50)
        }

        if type == .connected {
            activeDevices[device.stableKey] = device
            print("[DeviceMonitor] 🟢 CONNECTED: \(device.displayName) [Key: \(device.stableKey)] (\(device.connectionType.rawValue))\(device.formattedCapacity != nil ? " Capacity: \(device.formattedCapacity!)" : "")\(device.batteryPercentage != nil ? " Battery: \(device.batteryPercentage!)%" : "")")
        } else {
            activeDevices.removeValue(forKey: device.stableKey)
            print("[DeviceMonitor] 🔴 DISCONNECTED: \(device.displayName) [Key: \(device.stableKey)]")
        }

        eventSubject.send(event)
    }

    // MARK: - 1. Bluetooth Monitoring

    private func setupBluetoothMonitoring() {
        // Observe connections posted by BluetoothService
        NotificationCenter.default.publisher(for: .bluetoothDeviceDidConnect)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self = self, Defaults[.enableBluetoothDeviceShowcase] else { return }
                guard let device = notification.object as? IOBluetoothDevice else { return }
                self.handleBluetoothDevice(device, isConnected: true)
            }
            .store(in: &cancellables)

        // Observe disconnections posted by BluetoothService
        NotificationCenter.default.publisher(for: .bluetoothDeviceDidDisconnect)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self = self, Defaults[.enableBluetoothDeviceShowcase] else { return }
                guard let device = notification.object as? IOBluetoothDevice else { return }
                self.handleBluetoothDevice(device, isConnected: false)
            }
            .store(in: &cancellables)
    }

    private func handleBluetoothDevice(_ device: IOBluetoothDevice, isConnected: Bool) {
        guard let rawAddress = device.addressString, !rawAddress.isEmpty else { return }
        let normalizedAddress = rawAddress.lowercased().replacingOccurrences(of: ":", with: "-")
        let stableKey = "bt_\(normalizedAddress)"
        let name = device.nameOrAddress ?? "Bluetooth Device"

        if !isConnected {
            if let existing = activeDevices[stableKey] {
                publishEvent(type: .disconnected, device: existing)
            } else {
                let identity = DeviceIdentity(
                    stableKey: stableKey,
                    kind: classifyBluetoothKind(device, name: name),
                    displayName: name,
                    vendor: "Bluetooth",
                    model: name,
                    connectionType: .bluetooth
                )
                publishEvent(type: .disconnected, device: identity)
            }
            return
        }

        // Determine kind & battery
        let kind = classifyBluetoothKind(device, name: name)
        let battery = queryBluetoothBattery(normalizedAddress: normalizedAddress)

        let identity = DeviceIdentity(
            stableKey: stableKey,
            kind: kind,
            displayName: name,
            vendor: "Bluetooth",
            model: name,
            connectionType: .bluetooth,
            batteryPercentage: battery,
            iconName: kind.defaultIconName
        )
        publishEvent(type: .connected, device: identity)
    }

    private func classifyBluetoothKind(_ device: IOBluetoothDevice, name: String) -> DeviceKind {
        let lower = name.lowercased()
        if lower.contains("airpod") {
            if lower.contains("max") { return .headphones }
            return .earbuds
        } else if lower.contains("buds") || lower.contains("earphone") {
            return .earbuds
        } else if lower.contains("headphone") || lower.contains("wh-1000") || lower.contains("bose") {
            return .headphones
        } else if lower.contains("speaker") || lower.contains("soundlink") || lower.contains("boom") {
            return .speaker
        } else if lower.contains("mouse") {
            return .mouse
        } else if lower.contains("keyboard") {
            return .keyboard
        } else if lower.contains("iphone") || lower.contains("phone") {
            return .phone
        }

        switch device.deviceClassMajor {
        case 0x04: return .headphones
        case 0x05:
            if (device.deviceClassMinor & 0x40) != 0 { return .keyboard }
            if (device.deviceClassMinor & 0x80) != 0 { return .mouse }
            return .mouse
        case 0x02: return .phone
        default: return .generic
        }
    }

    private func queryBluetoothBattery(normalizedAddress: String) -> Int? {
        let serviceClasses = ["AppleDeviceManagementHIDEventService", "AppleBluetoothHIDDevice", "IOBluetoothHIDDriver"]
        for serviceClass in serviceClasses {
            var iterator: io_iterator_t = 0
            guard let matching = IOServiceMatching(serviceClass) else { continue }
            if IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess {
                while case let service = IOIteratorNext(iterator), service != 0 {
                    defer { IOObjectRelease(service) }
                    var props: Unmanaged<CFMutableDictionary>?
                    if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                       let dict = props?.takeRetainedValue() as? [String: Any] {
                        let addr = (dict["DeviceAddress"] as? String) ?? (dict["BluetoothDeviceAddress"] as? String)
                        let battery = (dict["BatteryPercent"] as? Int) ?? (dict["BatteryPercentSingle"] as? Int)
                        if let addr = addr, let battery = battery {
                            let norm = addr.lowercased().replacingOccurrences(of: ":", with: "-")
                            if norm == normalizedAddress {
                                IOObjectRelease(iterator)
                                return battery
                            }
                        }
                    }
                }
                IOObjectRelease(iterator)
            }
        }
        return nil
    }

    // MARK: - 2. Storage Monitoring (DiskArbitration + NSWorkspace)

    private func setupStorageMonitoring() {
        daSession = DASessionCreate(kCFAllocatorDefault)

        // Observe mount notifications
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self = self, Defaults[.enableStorageDeviceShowcase] else { return }
                guard let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
                self.handleVolumeMount(url)
            }
            .store(in: &cancellables)

        // Observe unmount notifications
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self = self, Defaults[.enableStorageDeviceShowcase] else { return }
                guard let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
                self.handleVolumeUnmount(url)
            }
            .store(in: &cancellables)
    }

    private func handleVolumeMount(_ url: URL) {
        guard let daSession = daSession else { return }
        guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, daSession, url as CFURL) else { return }
        guard let desc = DADiskCopyDescription(disk) as? [String: Any] else { return }

        // Filter out internal disk, disk images, and network volumes
        let isInternal = desc[kDADiskDescriptionDeviceInternalKey as String] as? Bool ?? false
        let isRemovable = desc[kDADiskDescriptionMediaRemovableKey as String] as? Bool ?? false
        let isNetwork = (desc[kDADiskDescriptionVolumeNetworkKey as String] as? Bool) ?? false
        let proto = desc[kDADiskDescriptionDeviceProtocolKey as String] as? String ?? ""

        // Ignore internal disk unless explicitly marked removable
        if isInternal && !isRemovable { return }
        // Ignore network volumes (SMB, AFP, NFS)
        if isNetwork || ["AFP", "SMB", "NFS"].contains(proto) { return }
        // Ignore disk images (.dmg) and virtual loopback volumes
        if proto == "Disk Image" || proto.contains("Virtual") { return }

        let bsdName = desc[kDADiskDescriptionMediaBSDNameKey as String] as? String ?? ""
        let parentBSD = extractParentBSD(from: bsdName)

        // Extract metadata
        let vendor = (desc[kDADiskDescriptionDeviceVendorKey as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = (desc[kDADiskDescriptionDeviceModelKey as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let volumeName = (desc[kDADiskDescriptionVolumeNameKey as String] as? String) ?? url.lastPathComponent
        let mediaSize = desc[kDADiskDescriptionMediaSizeKey as String] as? UInt64

        // Extract volume UUID
        var volumeUUID = ""
        if let cfuuid = desc[kDADiskDescriptionVolumeUUIDKey as String] {
            let descStr = String(describing: cfuuid)
            if let range = descStr.range(of: "[0-9A-F-]{36}", options: .regularExpression) {
                volumeUUID = String(descStr[range])
            }
        }
        if volumeUUID.isEmpty {
            if let uuidRes = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString {
                volumeUUID = uuidRes
            }
        }

        // Construct stable key: volume UUID + vendor/model
        let cleanVendor = sanitizeIdentifier(vendor.isEmpty ? "generic" : vendor)
        let cleanModel = sanitizeIdentifier(model.isEmpty ? "drive" : model)
        let stableKey: String
        if !volumeUUID.isEmpty {
            stableKey = "vol_\(volumeUUID.lowercased())_\(cleanVendor)_\(cleanModel)"
        } else {
            stableKey = "vol_disk_\(parentBSD)_\(cleanVendor)_\(cleanModel)"
        }

        // Classify kind: small USB stick vs external SSD/drive
        let kind: DeviceKind
        if proto.lowercased().contains("usb") && (mediaSize ?? 0) <= 64_000_000_000 && isRemovable {
            kind = .usbStick
        } else {
            kind = .ssdDrive
        }

        let displayName = volumeName.isEmpty ? "\(vendor) \(model)".trimmingCharacters(in: .whitespaces) : volumeName

        // Query available capacity and total capacity from volume URL
        let volValues = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        let freeSpace = volValues?.volumeAvailableCapacityForImportantUsage.map { UInt64($0) }
            ?? volValues?.volumeAvailableCapacity.map { UInt64($0) }
        let effectiveCapacity = volValues?.volumeTotalCapacity.map { UInt64($0) } ?? mediaSize

        let identity = DeviceIdentity(
            stableKey: stableKey,
            kind: kind,
            displayName: displayName.isEmpty ? "External Drive" : displayName,
            vendor: vendor.isEmpty ? "External Storage" : vendor,
            model: model.isEmpty ? proto : model,
            connectionType: .storage,
            capacityBytes: effectiveCapacity,
            freeSpaceBytes: freeSpace,
            mountPath: url.path,
            iconName: kind.defaultIconName
        )

        mountedVolumeKeys[url] = stableKey

        // Debounce multi-partition mounts for the same physical drive (e.g. disk4s1, disk4s2)
        storageMountDebounceWorkItems[parentBSD]?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.publishEvent(type: .connected, device: identity)
            self.storageMountDebounceWorkItems.removeValue(forKey: parentBSD)
        }
        storageMountDebounceWorkItems[parentBSD] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    private func handleVolumeUnmount(_ url: URL) {
        guard let stableKey = mountedVolumeKeys.removeValue(forKey: url) else { return }
        if let existing = activeDevices[stableKey] {
            publishEvent(type: .disconnected, device: existing)
        }
    }

    private func extractParentBSD(from bsdName: String) -> String {
        // e.g. "disk4s1s1" -> "disk4"
        if let match = bsdName.range(of: "disk[0-9]+", options: .regularExpression) {
            return String(bsdName[match])
        }
        return bsdName
    }

    private func sanitizeIdentifier(_ string: String) -> String {
        let allowed = CharacterSet.alphanumerics
        return string.lowercased().components(separatedBy: allowed.inverted).filter { !$0.isEmpty }.joined(separator: "-")
    }

    // MARK: - 3. USB Monitoring (IOKit non-storage devices)

    private func setupUSBMonitoring() {
        guard let notifyPort = IONotificationPortCreate(kIOMainPortDefault) else {
            print("[DeviceMonitor] ⚠️ Failed to create IONotificationPort")
            return
        }
        self.notifyPort = notifyPort

        let runLoopSource = IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue()
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)

        let refCon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        // C callback closures
        let onAddedCallback: IOServiceMatchingCallback = { refCon, iterator in
            guard let refCon = refCon else { return }
            let monitor = Unmanaged<DeviceMonitor>.fromOpaque(refCon).takeUnretainedValue()
            monitor.handleUSBIterator(iterator, isConnected: true)
        }

        let onRemovedCallback: IOServiceMatchingCallback = { refCon, iterator in
            guard let refCon = refCon else { return }
            let monitor = Unmanaged<DeviceMonitor>.fromOpaque(refCon).takeUnretainedValue()
            monitor.handleUSBIterator(iterator, isConnected: false)
        }

        // Register for both IOUSBHostDevice (macOS 12+) and IOUSBDevice (legacy)
        for className in ["IOUSBHostDevice", "IOUSBDevice"] {
            var addedIterator: io_iterator_t = 0
            if let matching = IOServiceMatching(className) as CFDictionary? {
                let kr = IOServiceAddMatchingNotification(
                    notifyPort,
                    kIOFirstMatchNotification,
                    matching,
                    onAddedCallback,
                    refCon,
                    &addedIterator
                )
                if kr == kIOReturnSuccess {
                    usbAddedIterators.append(addedIterator)
                    // Drain initial objects so we don't spam popups on app launch
                    drainIterator(addedIterator)
                }
            }

            var removedIterator: io_iterator_t = 0
            if let matching = IOServiceMatching(className) as CFDictionary? {
                let kr = IOServiceAddMatchingNotification(
                    notifyPort,
                    kIOTerminatedNotification,
                    matching,
                    onRemovedCallback,
                    refCon,
                    &removedIterator
                )
                if kr == kIOReturnSuccess {
                    usbRemovedIterators.append(removedIterator)
                    drainIterator(removedIterator)
                }
            }
        }
    }

    private func drainIterator(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            IOObjectRelease(service)
        }
    }

    nonisolated func handleUSBIterator(_ iterator: io_iterator_t, isConnected: Bool) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }

            var entryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &entryID)

            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
               let dict = props?.takeRetainedValue() as? [String: Any] {
                Task { @MainActor [weak self] in
                    self?.processUSBDevice(dict, registryID: entryID, isConnected: isConnected)
                }
            }
        }
    }

    private func processUSBDevice(_ dict: [String: Any], registryID: UInt64, isConnected: Bool) {
        guard Defaults[.enableUSBDeviceShowcase] else { return }

        let vid = (dict["idVendor"] as? UInt32) ?? (dict["vendorID"] as? UInt32) ?? 0
        let pid = (dict["idProduct"] as? UInt32) ?? (dict["productID"] as? UInt32) ?? 0
        let deviceClass = (dict["bDeviceClass"] as? UInt8) ?? (dict["deviceClass"] as? UInt8) ?? 0
        let isBuiltIn = (dict["Built-In"] as? Bool) ?? false

        // 1. Ignore USB Hubs (Class 9)
        if deviceClass == 9 { return }

        // 2. Ignore USB Mass Storage (Class 8) — already handled by DiskArbitration
        if deviceClass == 8 { return }

        // 3. Ignore built-in Apple devices (Vendor ID 0x05AC / internal coprocessors)
        if vid == 0x05AC || isBuiltIn { return }

        let prodName = (dict["USB Product Name"] as? String)
            ?? (dict["kUSBProductString"] as? String)
            ?? (dict["Product"] as? String)
            ?? "USB Device"
        let vendorName = (dict["USB Vendor Name"] as? String)
            ?? (dict["kUSBVendorString"] as? String)
            ?? (dict["Vendor"] as? String)
            ?? "USB"

        // Ignore generic root hubs or virtual descriptors
        if prodName.lowercased().contains("hub") || prodName.lowercased().contains("host controller") {
            return
        }

        let stableKey = String(format: "usb_%04x_%04x", vid, pid)

        if !isConnected {
            let keyToRemove = activeUSBRegistryIDs.removeValue(forKey: registryID) ?? stableKey
            if let existing = activeDevices[keyToRemove] {
                publishEvent(type: .disconnected, device: existing)
            }
            return
        }

        activeUSBRegistryIDs[registryID] = stableKey

        let kind = classifyUSBKind(name: prodName, deviceClass: deviceClass)
        let identity = DeviceIdentity(
            stableKey: stableKey,
            kind: kind,
            displayName: prodName,
            vendor: vendorName,
            model: String(format: "PID 0x%04X", pid),
            connectionType: .usb,
            iconName: kind.defaultIconName
        )

        publishEvent(type: .connected, device: identity)
    }

    private func classifyUSBKind(name: String, deviceClass: UInt8) -> DeviceKind {
        let lower = name.lowercased()
        if lower.contains("mouse") { return .mouse }
        if lower.contains("keyboard") { return .keyboard }
        if lower.contains("headset") || lower.contains("audio") || lower.contains("dac") || lower.contains("mic") {
            return .speaker
        }
        if lower.contains("controller") || lower.contains("gamepad") { return .generic }
        if lower.contains("iphone") || lower.contains("ipad") { return .phone }
        return .generic
    }

    // MARK: - Debug Helper

    public func clearEventLog() {
        recentEvents.removeAll()
    }
}

// MARK: - Debug Log View

public struct DeviceMonitorDebugView: View {
    @ObservedObject var monitor = DeviceMonitor.shared

    @Default(.enableBluetoothDeviceShowcase) var enableBT
    @Default(.enableStorageDeviceShowcase) var enableStorage
    @Default(.enableUSBDeviceShowcase) var enableUSB

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Source Status Badges
            HStack(spacing: 8) {
                SourceStatusChip(title: "Bluetooth", enabled: enableBT, icon: "antenna.radiowaves.left.and.right")
                SourceStatusChip(title: "Storage", enabled: enableStorage, icon: "internaldrive")
                SourceStatusChip(title: "USB", enabled: enableUSB, icon: "cable.connector")
                Spacer()
                Button("Clear Log") {
                    monitor.clearEventLog()
                }
                .controlSize(.small)
            }

            Divider()

            // Active Connected Devices
            VStack(alignment: .leading, spacing: 6) {
                Text("CURRENTLY CONNECTED (\(monitor.activeDevices.count))")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                if monitor.activeDevices.isEmpty {
                    Text("No devices currently connected")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(monitor.activeDevices.values)) { device in
                                ActiveDeviceCard(device: device)
                            }
                        }
                    }
                }
            }

            Divider()

            // Chronological Event Stream
            VStack(alignment: .leading, spacing: 6) {
                Text("DETECTION EVENT STREAM (\(monitor.recentEvents.count))")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                if monitor.recentEvents.isEmpty {
                    Text("Plug or connect a device to see detection events...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
                } else {
                    List(monitor.recentEvents) { event in
                        EventLogRow(event: event)
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                    .frame(minHeight: 180)
                }
            }
        }
        .padding(14)
        .navigationTitle("Device Detection Log")
    }
}

private struct SourceStatusChip: View {
    let title: String
    let enabled: Bool
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(enabled ? Color.green : Color.secondary)
                .frame(width: 6, height: 6)
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(title)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
    }
}

private struct ActiveDeviceCard: View {
    let device: DeviceIdentity

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: device.iconName)
                    .font(.system(size: 13))
                Text(device.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            Text(device.stableKey)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack {
                Text(device.connectionType.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                if let cap = device.formattedCapacity {
                    Text(cap)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                if let bat = device.batteryPercentage {
                    Text("\(bat)%")
                        .font(.system(size: 9))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(8)
        .frame(width: 170, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
        )
    }
}

private struct EventLogRow: View {
    let event: DeviceEvent

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: event.timestamp)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(timeString)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)

            // Event badge
            Text(event.type.rawValue.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(event.type == .connected ? Color.green : Color.red)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(event.type == .connected ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Image(systemName: event.device.iconName)
                .font(.system(size: 11))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.device.displayName)
                    .font(.system(size: 11, weight: .medium))
                Text("\(event.device.connectionType.rawValue) • \(event.device.stableKey)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let cap = event.device.formattedCapacity {
                Text(cap)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if let bat = event.device.batteryPercentage {
                Text("\(bat)%")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
    }
}
