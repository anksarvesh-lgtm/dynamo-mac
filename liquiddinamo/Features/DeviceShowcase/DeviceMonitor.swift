//
//  DeviceMonitor.swift
//  boringNotch
//
//  Created for Boring Notch
//

import AppKit
import Combine
import CoreBluetooth
import Defaults
import DiskArbitration
import Foundation
import GameController
import IOBluetooth
import IOKit
import IOKit.usb
import SwiftUI

// MARK: - Device Models

public enum DeviceKind: String, Codable, CaseIterable, Identifiable {
    case airpods = "AirPods"
    case earbuds = "Earbuds"
    case earphones = "Earphones"
    case neckband = "Neckband"
    case headphones = "Headphones"
    case speaker = "Speaker"
    case ssdDrive = "SSD / Drive"
    case usbStick = "USB Flash Drive"
    case mouse = "Mouse"
    case trackpad = "Trackpad"
    case keyboard = "Keyboard"
    case phone = "Phone"
    case androidPhone = "Android"
    case tablet = "Tablet"
    case monitor = "Display"
    case gameController = "Game Controller"
    case printer = "Printer"
    case charger = "Power Adapter"
    case generic = "Generic"

    public var id: String { rawValue }

    public var defaultIconName: String {
        switch self {
        case .airpods: return "airpodspro"
        case .earbuds: return "earbuds"
        case .earphones: return "headphones"
        case .neckband: return "headphones"
        case .headphones: return "headphones"
        case .speaker: return "speaker.wave.2.fill"
        case .ssdDrive: return "internaldrive"
        case .usbStick: return "externaldrive.fill"
        case .mouse: return "computermouse.fill"
        case .trackpad: return "hand.point.up.left.fill"
        case .keyboard: return "keyboard"
        case .phone: return "iphone"
        case .androidPhone: return "phone.fill"
        case .tablet: return "ipad"
        case .monitor: return "display"
        case .gameController: return "gamecontroller.fill"
        case .printer: return "printer.fill"
        case .charger: return "powerplug.fill"
        case .generic: return "cable.connector"
        }
    }
}

public enum ConnectionType: String, Codable, CaseIterable {
    case bluetooth = "Bluetooth"
    case storage = "Storage"
    case usb = "USB"
    case display = "DisplayPort / HDMI"
    case power = "AC Power"
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
    public let filesystem: String?
    public let mountPath: String?
    public let batteryPercentage: Int?
    public let leftBattery: Int?
    public let rightBattery: Int?
    public let caseBattery: Int?
    public let resolution: String?
    public let scaledResolution: String?
    public let refreshRate: Double?
    public let iconName: String
    public let chargerWatts: Int?
    public let chargerPort: String?
    public let isChargingState: Bool?
    public let chargingVoltage: Double?
    public let chargingCurrent: Double?
    public let chargingPowerWatts: Double?
    public let chargingStatusDescription: String?
    public let chargingMethodType: String?

    public init(
        stableKey: String,
        kind: DeviceKind,
        displayName: String,
        vendor: String,
        model: String,
        connectionType: ConnectionType,
        capacityBytes: UInt64? = nil,
        freeSpaceBytes: UInt64? = nil,
        filesystem: String? = nil,
        mountPath: String? = nil,
        batteryPercentage: Int? = nil,
        leftBattery: Int? = nil,
        rightBattery: Int? = nil,
        caseBattery: Int? = nil,
        resolution: String? = nil,
        scaledResolution: String? = nil,
        refreshRate: Double? = nil,
        iconName: String? = nil,
        chargerWatts: Int? = nil,
        chargerPort: String? = nil,
        isChargingState: Bool? = nil,
        chargingVoltage: Double? = nil,
        chargingCurrent: Double? = nil,
        chargingPowerWatts: Double? = nil,
        chargingStatusDescription: String? = nil,
        chargingMethodType: String? = nil
    ) {
        self.stableKey = stableKey
        self.kind = kind
        self.displayName = displayName
        self.vendor = vendor
        self.model = model
        self.connectionType = connectionType
        self.capacityBytes = capacityBytes
        self.freeSpaceBytes = freeSpaceBytes
        self.filesystem = filesystem
        self.mountPath = mountPath
        self.batteryPercentage = batteryPercentage
        self.leftBattery = leftBattery
        self.rightBattery = rightBattery
        self.caseBattery = caseBattery
        self.resolution = resolution
        self.scaledResolution = scaledResolution
        self.refreshRate = refreshRate
        self.iconName = iconName ?? kind.defaultIconName
        self.chargerWatts = chargerWatts
        self.chargerPort = chargerPort
        self.isChargingState = isChargingState
        self.chargingVoltage = chargingVoltage
        self.chargingCurrent = chargingCurrent
        self.chargingPowerWatts = chargingPowerWatts
        self.chargingStatusDescription = chargingStatusDescription
        self.chargingMethodType = chargingMethodType
    }

    public var usedSpaceBytes: UInt64? {
        guard let cap = capacityBytes, let free = freeSpaceBytes, cap >= free else { return nil }
        return cap - free
    }

    public var formattedCapacity: String? {
        guard let bytes = capacityBytes, bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    public var formattedFreeSpace: String? {
        guard let bytes = freeSpaceBytes, bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    public var formattedUsedSpace: String? {
        guard let bytes = usedSpaceBytes else { return nil }
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

// MARK: - Bluetooth Disconnect Observer Helper
private final class BluetoothDeviceDisconnectObserver: NSObject {
    static let shared = BluetoothDeviceDisconnectObserver()
    private var registeredAddresses = Set<String>()

    func register(device: IOBluetoothDevice) {
        guard let address = device.addressString, !registeredAddresses.contains(address) else { return }
        registeredAddresses.insert(address)
        device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
    }

    func unregister(address: String) {
        registeredAddresses.remove(address)
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        Task { @MainActor in
            let name = device.nameOrAddress ?? "Unknown Bluetooth Device"
            if let address = device.addressString {
                self.registeredAddresses.remove(address)
            }
            print("🔍 [Bluetooth Audit] Disconnect notification received for: \(name)")
            DeviceMonitor.shared.handleBluetoothDevice(device, isConnected: false)
            DeviceMonitor.shared.refreshBluetoothDevices()
        }
    }
}

// MARK: - CoreBluetooth Audit Helper
@MainActor
final class CoreBluetoothAuditHelper: NSObject, CBCentralManagerDelegate {
    static let shared = CoreBluetoothAuditHelper()

    private var central: CBCentralManager?
    private(set) var bluetoothState: CBManagerState = .unknown

    var authorizationStatusDescription: String {
        if #available(macOS 10.15, *) {
            switch CBCentralManager.authorization {
            case .allowedAlways: return "allowedAlways (Authorized)"
            case .denied: return "denied (Unauthorized)"
            case .restricted: return "restricted"
            case .notDetermined: return "notDetermined"
            @unknown default: return "unknown"
            }
        }
        return "N/A (< macOS 10.15)"
    }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.bluetoothState = central.state
            let stateStr: String
            switch central.state {
            case .poweredOn: stateStr = "poweredOn"
            case .poweredOff: stateStr = "poweredOff"
            case .unauthorized: stateStr = "unauthorized"
            case .unsupported: stateStr = "unsupported"
            case .resetting: stateStr = "resetting"
            case .unknown: stateStr = "unknown"
            @unknown default: stateStr = "other"
            }
            print("🔍 [Bluetooth Audit] CoreBluetooth CentralManager state: \(stateStr), Auth: \(self.authorizationStatusDescription)")
            DeviceMonitor.shared.refreshBluetoothDevices()
        }
    }

    func retrieveConnectedPeripherals() -> [CBPeripheral] {
        guard let central = central, central.state == .poweredOn else { return [] }
        let services = [
            CBUUID(string: "180F"), // Battery Service
            CBUUID(string: "1812"), // HID Service
            CBUUID(string: "180A"), // Device Info Service
            CBUUID(string: "1800")  // Generic Access
        ]
        return central.retrieveConnectedPeripherals(withServices: services)
    }
}

// MARK: - Device Monitor Service

@MainActor
public final class DeviceMonitor: ObservableObject {
    public static let shared = DeviceMonitor()

    @Published public private(set) var activeDevices: [String: DeviceIdentity] = [:]
    @Published public private(set) var recentEvents: [DeviceEvent] = []
    @Published public private(set) var latestEvent: DeviceEvent?

    public var sortedActiveDevices: [DeviceIdentity] {
        return activeDevices.values.sorted { d1, d2 in
            // Displays first (main display first, then connected external displays)
            if d1.kind == .monitor && d2.kind != .monitor { return true }
            if d1.kind != .monitor && d2.kind == .monitor { return false }
            if d1.kind == .monitor && d2.kind == .monitor {
                let d1IsMain = d1.model.contains("Main") || d1.displayName.contains("Built-in")
                let d2IsMain = d2.model.contains("Main") || d2.displayName.contains("Built-in")
                if d1IsMain && !d2IsMain { return true }
                if !d1IsMain && d2IsMain { return false }
                return d1.displayName < d2.displayName
            }
            // Chargers second
            if d1.kind == .charger && d2.kind != .charger { return true }
            if d1.kind != .charger && d2.kind == .charger { return false }
            // Storage third
            if (d1.kind == .ssdDrive || d1.kind == .usbStick) && !(d2.kind == .ssdDrive || d2.kind == .usbStick) { return true }
            if !(d1.kind == .ssdDrive || d1.kind == .usbStick) && (d2.kind == .ssdDrive || d2.kind == .usbStick) { return false }
            return d1.displayName < d2.displayName
        }
    }

    public let eventSubject = PassthroughSubject<DeviceEvent, Never>()

    // Bluetooth background polling
    private var btPollingTimer: Timer?

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
        setupDisplayMonitoring()
        setupGameControllerMonitoring()
        setupAirPodsMonitoring()
        setupPowerAdapterMonitoring()
    }

    deinit {
        btPollingTimer?.invalidate()
        btPollingTimer = nil
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

    // MARK: - Power Adapter Management
    public func registerChargerDevice(_ device: DeviceIdentity) {
        if activeDevices[device.stableKey] == nil {
            publishEvent(type: .connected, device: device)
        } else {
            activeDevices[device.stableKey] = device
        }
    }

    public func unregisterChargerDevice() {
        if let existing = activeDevices["power_adapter"] {
            publishEvent(type: .disconnected, device: existing)
        }
    }

    private func setupPowerAdapterMonitoring() {
        ChargingIntelligenceService.shared.$currentChargerIdentity
            .receive(on: RunLoop.main)
            .sink { [weak self] charger in
                guard let self = self else { return }
                if let charger = charger {
                    self.registerChargerDevice(charger)
                } else {
                    self.unregisterChargerDevice()
                }
            }
            .store(in: &cancellables)
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
            Task {
                await DeviceModelStore.shared.recordDeviceSeen(device: device)
            }
        } else {
            activeDevices.removeValue(forKey: device.stableKey)
            print("[DeviceMonitor] 🔴 DISCONNECTED: \(device.displayName) [Key: \(device.stableKey)]")
        }

        eventSubject.send(event)
    }

    // MARK: - 1. Bluetooth Monitoring

    private func setupBluetoothMonitoring() {
        // Initial real-time enumeration
        refreshBluetoothDevices()

        // 2-second background sync timer to guarantee real-time detection & immediate disconnect removal
        btPollingTimer?.invalidate()
        btPollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshBluetoothDevices()
            }
        }

        // Observe connections posted by BluetoothService
        NotificationCenter.default.publisher(for: .bluetoothDeviceDidConnect)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                if let device = notification.object as? IOBluetoothDevice {
                    self.handleBluetoothDevice(device, isConnected: true)
                }
                self.refreshBluetoothDevices()
            }
            .store(in: &cancellables)

        // Observe disconnections posted by BluetoothService
        NotificationCenter.default.publisher(for: .bluetoothDeviceDidDisconnect)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                if let device = notification.object as? IOBluetoothDevice {
                    self.handleBluetoothDevice(device, isConnected: false)
                }
                self.refreshBluetoothDevices()
            }
            .store(in: &cancellables)

        // Refresh on system wake
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshBluetoothDevices()
            }
            .store(in: &cancellables)
    }

    public func refreshBluetoothDevices() {
        _ = CoreBluetoothAuditHelper.shared
        var currentKeys = Set<String>()

        // 1. Enumerate IOBluetoothDevice paired devices (Real connected devices only)
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        for device in paired {
            guard device.isConnected() else { continue }
            guard let rawAddress = device.addressString, !rawAddress.isEmpty else { continue }
            let normalizedAddress = rawAddress.lowercased().replacingOccurrences(of: ":", with: "-")
            let stableKey = "bt_\(normalizedAddress)"
            currentKeys.insert(stableKey)

            // Register native disconnect notification observer
            BluetoothDeviceDisconnectObserver.shared.register(device: device)

            let name = device.nameOrAddress ?? "Bluetooth Device"
            let kind = classifyBluetoothKind(device, name: name)
            let bat = queryBluetoothBattery(device: device, normalizedAddress: normalizedAddress)

            let identity = DeviceIdentity(
                stableKey: stableKey,
                kind: kind,
                displayName: name,
                vendor: "Bluetooth",
                model: name,
                connectionType: .bluetooth,
                batteryPercentage: bat.percentage,
                leftBattery: bat.left,
                rightBattery: bat.right,
                caseBattery: bat.caseBat,
                iconName: kind.defaultIconName
            )

            let isNew = activeDevices[stableKey] == nil
            let batteryChanged = activeDevices[stableKey]?.batteryPercentage != bat.percentage
            if isNew || batteryChanged {
                publishEvent(type: .connected, device: identity)
            }
        }

        // 1b. Also incorporate devices reported by BluetoothService
        for btInfo in BluetoothService.shared.connectedDevices where btInfo.isConnected {
            let normalizedAddress = btInfo.id.lowercased().replacingOccurrences(of: ":", with: "-")
            let stableKey = "bt_\(normalizedAddress)"
            currentKeys.insert(stableKey)

            if activeDevices[stableKey] == nil {
                let kind = classifyNameKind(btInfo.name)
                let identity = DeviceIdentity(
                    stableKey: stableKey,
                    kind: kind,
                    displayName: btInfo.name,
                    vendor: "Bluetooth",
                    model: btInfo.name,
                    connectionType: .bluetooth,
                    batteryPercentage: btInfo.batteryPercentage,
                    iconName: kind.defaultIconName
                )
                publishEvent(type: .connected, device: identity)
            }
        }

        // 2. Enumerate CoreBluetooth connected peripherals (Strict filter: only truly connected real peripherals)
        let cbPeripherals = CoreBluetoothAuditHelper.shared.retrieveConnectedPeripherals()
        for peripheral in cbPeripherals {
            guard peripheral.state == .connected else { continue }
            guard let rawName = peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawName.isEmpty,
                  rawName != "BLE Accessory",
                  rawName != "Unknown Device",
                  !rawName.hasPrefix("Apple Continuity"),
                  !rawName.hasPrefix("Nearby") else {
                continue
            }

            // Deduplicate if already represented in activeDevices by IOBluetooth paired device
            let isAlreadyTracked = activeDevices.values.contains { existing in
                existing.displayName.caseInsensitiveCompare(rawName) == .orderedSame
            }
            guard !isAlreadyTracked else { continue }

            let key = "cb_\(peripheral.identifier.uuidString.lowercased())"
            currentKeys.insert(key)
            if activeDevices[key] == nil {
                let kind = classifyNameKind(rawName)
                let identity = DeviceIdentity(
                    stableKey: key,
                    kind: kind,
                    displayName: rawName,
                    vendor: "Bluetooth LE",
                    model: rawName,
                    connectionType: .bluetooth,
                    batteryPercentage: nil,
                    iconName: kind.defaultIconName
                )
                publishEvent(type: .connected, device: identity)
            }
        }

        // 3. Retain AirPods if connected via AirPodsService
        if AirPodsService.shared.state.isConnected {
            currentKeys.insert("airpods_current")
        }

        // 4. Remove disconnected Bluetooth devices
        for (key, device) in activeDevices where (key.hasPrefix("bt_") || key.hasPrefix("cb_")) {
            if !currentKeys.contains(key) {
                print("🔍 [Bluetooth Audit] Disconnection detected: \(device.displayName) | Key: \(key)")
                publishEvent(type: .disconnected, device: device)
            }
        }

        // 5. Temporary Audit Logging (as required by audit specification)
        let btDevices = activeDevices.values.filter { $0.connectionType == .bluetooth }
        print("🔍 [Bluetooth Audit] Connected device count: \(btDevices.count)")
        for dev in btDevices {
            print("🔍 [Bluetooth Audit] Device name: \(dev.displayName)")
            print("🔍 [Bluetooth Audit] Device type: \(dev.kind.rawValue)")
            print("🔍 [Bluetooth Audit] Battery information: \(dev.batteryPercentage.map { "\($0)%" } ?? "N/A")")
            print("🔍 [Bluetooth Audit] Connection state: Connected")
        }
    }

    func handleBluetoothDevice(_ device: IOBluetoothDevice, isConnected: Bool) {
        guard let rawAddress = device.addressString, !rawAddress.isEmpty else { return }
        let normalizedAddress = rawAddress.lowercased().replacingOccurrences(of: ":", with: "-")
        let stableKey = "bt_\(normalizedAddress)"
        let name = device.nameOrAddress ?? "Bluetooth Device"

        if !isConnected {
            BluetoothDeviceDisconnectObserver.shared.unregister(address: rawAddress)
            if let existing = activeDevices[stableKey] {
                print("🔍 [Bluetooth Audit] Disconnection event: \(existing.displayName)")
                publishEvent(type: .disconnected, device: existing)
            }
            return
        }

        BluetoothDeviceDisconnectObserver.shared.register(device: device)
        let kind = classifyBluetoothKind(device, name: name)
        let bat = queryBluetoothBattery(device: device, normalizedAddress: normalizedAddress)

        let identity = DeviceIdentity(
            stableKey: stableKey,
            kind: kind,
            displayName: name,
            vendor: "Bluetooth",
            model: name,
            connectionType: .bluetooth,
            batteryPercentage: bat.percentage,
            leftBattery: bat.left,
            rightBattery: bat.right,
            caseBattery: bat.caseBat,
            iconName: kind.defaultIconName
        )
        publishEvent(type: .connected, device: identity)
    }

    private func classifyNameKind(_ name: String) -> DeviceKind {
        let lower = name.lowercased()
        if lower.contains("airpod") {
            if lower.contains("max") { return .headphones }
            return .airpods
        } else if lower.contains("trackpad") {
            return .trackpad
        } else if lower.contains("printer") {
            return .printer
        } else if lower.contains("neckband") || lower.contains("wireless") || lower.contains("bullets") || lower.contains("rockerz") {
            return .neckband
        } else if lower.contains("earphone") || lower.contains("in-ear") {
            return .earphones
        } else if lower.contains("buds") || lower.contains("airdot") || lower.contains("earbud") {
            return .earbuds
        } else if lower.contains("headphone") || lower.contains("wh-1000") || lower.contains("bose") || lower.contains("quietcomfort") || lower.contains("xm4") || lower.contains("xm5") || lower.contains("solo") || lower.contains("studio") {
            return .headphones
        } else if lower.contains("speaker") || lower.contains("soundlink") || lower.contains("boom") || lower.contains("jbl") || lower.contains("charge") || lower.contains("flip") || lower.contains("echo") || lower.contains("homepod") {
            return .speaker
        } else if lower.contains("controller") || lower.contains("gamepad") || lower.contains("dualsense") || lower.contains("dualshock") || lower.contains("xbox") || lower.contains("switch") {
            return .gameController
        } else if lower.contains("mouse") {
            return .mouse
        } else if lower.contains("keyboard") {
            return .keyboard
        } else if lower.contains("ipad") {
            return .tablet
        } else if lower.contains("android") || lower.contains("pixel") || lower.contains("galaxy") || lower.contains("samsung") || lower.contains("redmi") || lower.contains("xiaomi") || lower.contains("oneplus") || lower.contains("oppo") || lower.contains("vivo") || lower.contains("realme") || lower.contains("motorola") || lower.contains("moto ") || lower.contains("nothing phone") || lower.contains("honor") || lower.contains("sony") || lower.contains("xperia") || lower.contains("huawei") || lower.contains("poco") || lower.contains("infinix") || lower.contains("tecno") || lower.contains("asus") || lower.contains("rog phone") || lower.contains("mtp") || lower.contains("sm-") {
            return .androidPhone
        } else if lower.contains("iphone") || lower.contains("phone") || lower.contains("ios") {
            return .phone
        }
        return .generic
    }

    private func classifyBluetoothKind(_ device: IOBluetoothDevice, name: String) -> DeviceKind {
        let kindFromName = classifyNameKind(name)
        if kindFromName != .generic {
            return kindFromName
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

    private func queryBluetoothBattery(device: IOBluetoothDevice, normalizedAddress: String) -> (percentage: Int?, left: Int?, right: Int?, caseBat: Int?) {
        let ioResult = queryIORegistryBattery(normalizedAddress: normalizedAddress)
        if ioResult.percentage != nil || ioResult.left != nil || ioResult.right != nil || ioResult.caseBat != nil {
            return ioResult
        }

        var percentage: Int? = nil
        if let single = device.value(forKey: "batteryPercentSingle") as? Int, single > 0, single <= 100 {
            percentage = single
        } else if let combined = device.value(forKey: "batteryPercentCombined") as? Int, combined > 0, combined <= 100 {
            percentage = combined
        }

        var left: Int? = nil
        if let l = device.value(forKey: "batteryPercentLeft") as? Int, l > 0, l <= 100 {
            left = l
        }

        var right: Int? = nil
        if let r = device.value(forKey: "batteryPercentRight") as? Int, r > 0, r <= 100 {
            right = r
        }

        var caseB: Int? = nil
        if let c = device.value(forKey: "batteryPercentCase") as? Int, c > 0, c <= 100 {
            caseB = c
        }

        if percentage == nil {
            percentage = left ?? right ?? caseB
        }

        return (percentage, left, right, caseB)
    }

    private func queryIORegistryBattery(normalizedAddress: String) -> (percentage: Int?, left: Int?, right: Int?, caseBat: Int?) {
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
                        if let addr = addr {
                            let norm = addr.lowercased().replacingOccurrences(of: ":", with: "-")
                            if norm == normalizedAddress {
                                let single = (dict["BatteryPercent"] as? Int) ?? (dict["BatteryPercentSingle"] as? Int) ?? (dict["BatteryPercentCombined"] as? Int)
                                let left = dict["BatteryPercentLeft"] as? Int
                                let right = dict["BatteryPercentRight"] as? Int
                                let caseBat = dict["BatteryPercentCase"] as? Int
                                IOObjectRelease(iterator)
                                return (single ?? left ?? right, left, right, caseBat)
                            }
                        }
                    }
                }
                IOObjectRelease(iterator)
            }
        }
        return (nil, nil, nil, nil)
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

        // Initial scan of currently mounted external volumes
        let existingVolumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsRemovableKey, .volumeIsInternalKey], options: [.skipHiddenVolumes]) ?? []
        for volURL in existingVolumes {
            handleVolumeMount(volURL)
        }
    }

    private func handleVolumeMount(_ url: URL) {
        let path = url.path
        if path == "/" || path.hasPrefix("/System") || path.hasPrefix("/private") || path.hasPrefix("/Volumes/Recovery") || path.hasPrefix("/Volumes/Preboot") || path.hasPrefix("/Volumes/Data") || path.hasPrefix("/Volumes/Macintosh HD") || path.hasPrefix("/Volumes/Update") || path.contains(".timemachine") {
            return
        }
        if url.pathExtension.lowercased() == "dmg" { return }

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

        // Query available capacity, total capacity, and filesystem from volume URL
        let volValues = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeLocalizedFormatDescriptionKey, .volumeTypeNameKey])
        let freeSpace = volValues?.volumeAvailableCapacityForImportantUsage.map { UInt64($0) }
            ?? volValues?.volumeAvailableCapacity.map { UInt64($0) }
        let effectiveCapacity = volValues?.volumeTotalCapacity.map { UInt64($0) } ?? mediaSize
        let filesystem = volValues?.volumeLocalizedFormatDescription ?? volValues?.volumeTypeName

        var resolvedCapacity = effectiveCapacity
        var resolvedFreeSpace = freeSpace
        var resolvedFilesystem = filesystem

        var stat = statfs()
        if statfs(url.path, &stat) == 0 {
            let bsize = UInt64(max(0, stat.f_bsize))
            let statTotal = UInt64(max(0, stat.f_blocks)) * bsize
            let statFree = UInt64(max(0, stat.f_bavail)) * bsize
            if (resolvedCapacity == nil || resolvedCapacity == 0) && statTotal > 0 {
                resolvedCapacity = statTotal
            }
            if (resolvedFreeSpace == nil || resolvedFreeSpace == 0) && statFree > 0 {
                resolvedFreeSpace = statFree
            }
            if resolvedFilesystem == nil || resolvedFilesystem?.isEmpty == true {
                withUnsafePointer(to: &stat.f_fstypename) { ptr in
                    ptr.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { cStr in
                        resolvedFilesystem = String(cString: cStr)
                    }
                }
            }
        }

        let identity = DeviceIdentity(
            stableKey: stableKey,
            kind: kind,
            displayName: displayName.isEmpty ? "External Drive" : displayName,
            vendor: vendor.isEmpty ? "External Storage" : vendor,
            model: model.isEmpty ? proto : model,
            connectionType: .storage,
            capacityBytes: resolvedCapacity,
            freeSpaceBytes: resolvedFreeSpace,
            filesystem: resolvedFilesystem,
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

        let prodName = (dict["USB Product Name"] as? String)
            ?? (dict["kUSBProductString"] as? String)
            ?? (dict["Product"] as? String)
            ?? "USB Device"
        let vendorName = (dict["USB Vendor Name"] as? String)
            ?? (dict["kUSBVendorString"] as? String)
            ?? (dict["Vendor"] as? String)
            ?? "USB"

        // 3. Ignore internal built-in Apple devices (trackpad, internal keyboard, sensor hubs)
        if isBuiltIn { return }
        if vid == 0x05AC {
            let lowerProd = prodName.lowercased()
            let isAppleMobile = (pid >= 0x1280 && pid <= 0x12DF) || pid == 0x8600 || lowerProd.contains("iphone") || lowerProd.contains("ipad") || lowerProd.contains("ipod") || lowerProd.contains("apple mobile")
            if !isAppleMobile {
                if lowerProd.contains("internal") || lowerProd.contains("keyboard") || lowerProd.contains("trackpad") || lowerProd.contains("ambient") || lowerProd.contains("sensor") || lowerProd.contains("touch bar") || lowerProd.contains("t2") || lowerProd.contains("facetime") {
                    return
                }
            }
        }

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

        let kind = classifyUSBKind(name: prodName, vendor: vendorName, vid: vid, pid: pid, deviceClass: deviceClass)

        var finalDisplayName = prodName
        var finalVendor = vendorName
        if kind == .phone {
            if finalDisplayName == "USB Device" || finalDisplayName.isEmpty {
                finalDisplayName = "iPhone"
            }
            if finalVendor == "USB" || finalVendor.isEmpty {
                finalVendor = "Apple"
            }
        } else if kind == .tablet && vid == 0x05AC {
            if finalDisplayName == "USB Device" || finalDisplayName.isEmpty {
                finalDisplayName = "iPad"
            }
            if finalVendor == "USB" || finalVendor.isEmpty {
                finalVendor = "Apple"
            }
        } else if kind == .androidPhone {
            if finalVendor == "USB" || finalVendor.isEmpty {
                switch vid {
                case 0x18D1: finalVendor = "Google"
                case 0x04E8: finalVendor = "Samsung"
                case 0x2717: finalVendor = "Xiaomi"
                case 0x22D9: finalVendor = "OnePlus"
                case 0x2D95: finalVendor = "Vivo"
                case 0x22B8: finalVendor = "Motorola"
                case 0x12D1: finalVendor = "Huawei"
                case 0x0FCE: finalVendor = "Sony"
                case 0x1004: finalVendor = "LG"
                case 0x2A70: finalVendor = "Nothing"
                default: finalVendor = "Android"
                }
            }
            if finalDisplayName == "USB Device" || finalDisplayName.isEmpty {
                finalDisplayName = "\(finalVendor) Phone"
            }
        }

        let identity = DeviceIdentity(
            stableKey: stableKey,
            kind: kind,
            displayName: finalDisplayName,
            vendor: finalVendor,
            model: String(format: "PID 0x%04X", pid),
            connectionType: .usb,
            iconName: kind.defaultIconName
        )

        publishEvent(type: .connected, device: identity)
    }

    private func classifyUSBKind(name: String, vendor: String = "", vid: UInt32 = 0, pid: UInt32 = 0, deviceClass: UInt8 = 0) -> DeviceKind {
        let lower = (name + " " + vendor).lowercased()
        if deviceClass == 0x07 || lower.contains("printer") { return .printer }
        if lower.contains("trackpad") { return .trackpad }
        if lower.contains("mouse") { return .mouse }
        if lower.contains("keyboard") { return .keyboard }
        if lower.contains("earphone") { return .earphones }
        if lower.contains("airpod") { return .airpods }
        if lower.contains("headset") || lower.contains("audio") || lower.contains("dac") || lower.contains("mic") {
            return .headphones
        }
        if lower.contains("controller") || lower.contains("gamepad") || lower.contains("dualsense") || lower.contains("xbox") || lower.contains("joystick") {
            return .gameController
        }

        // Apple iOS Devices by VID/PID and string
        if vid == 0x05AC {
            if (pid >= 0x12a0 && pid <= 0x12af) || lower.contains("ipad") {
                return .tablet
            }
            if (pid >= 0x1280 && pid <= 0x12df) || pid == 0x8600 || lower.contains("iphone") || lower.contains("ipod") || lower.contains("apple mobile") {
                return .phone
            }
        }

        // Android Devices by VID and string
        let androidVIDs: Set<UInt32> = [
            0x18D1, // Google
            0x04E8, // Samsung
            0x2717, // Xiaomi
            0x22D9, // OnePlus / Oppo / Realme
            0x2D95, // Vivo
            0x22B8, // Motorola
            0x12D1, // Huawei
            0x0FCE, // Sony
            0x1004, // LG
            0x0BB4, // HTC
            0x2A70, // Nothing
            0x1782, // Transsion (Tecno/Infinix)
            0x2A45, // Meizu
            0x19D2, // ZTE
            0x0E8D, // MediaTek
            0x05C6  // Qualcomm
        ]

        if androidVIDs.contains(vid) {
            return .androidPhone
        }

        if lower.contains("ipad") { return .tablet }
        if lower.contains("iphone") || lower.contains("ipod") || lower.contains("apple mobile") { return .phone }
        if lower.contains("android") || lower.contains("pixel") || lower.contains("galaxy") || lower.contains("samsung") || lower.contains("redmi") || lower.contains("xiaomi") || lower.contains("oneplus") || lower.contains("oppo") || lower.contains("vivo") || lower.contains("motorola") || lower.contains("xperia") || lower.contains("nothing phone") || lower.contains("mtp") {
            return .androidPhone
        }
        if lower.contains("phone") || lower.contains("mobile") { return .phone }
        return .generic
    }

    // MARK: - 4. Display Monitoring

    private var hasCompletedInitialDisplayScan = false

    private func setupDisplayMonitoring() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshConnectedDisplays(isInitialScan: false)
            }
            .store(in: &cancellables)

        refreshConnectedDisplays(isInitialScan: true)
        hasCompletedInitialDisplayScan = true
    }

    private func refreshConnectedDisplays(isInitialScan: Bool = false) {
        MultiDisplayBrightnessService.shared.refreshDisplays()
        var currentDisplayKeys: Set<String> = []

        for screen in NSScreen.screens {
            let screenNumber: CGDirectDisplayID
            if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                screenNumber = CGDirectDisplayID(num.uint32Value)
            } else if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                screenNumber = num
            } else {
                continue
            }
            let isBuiltIn = CGDisplayIsBuiltin(screenNumber) != 0 || screen.safeAreaInsets.top > 0
            // User requirement: Do NOT show built-in display in connected devices shelf, ONLY external displays
            if isBuiltIn {
                continue
            }
            let isMain = screen == NSScreen.main || CGDisplayIsMain(screenNumber) != 0

            let stableKey = "display_\(screenNumber)"
            currentDisplayKeys.insert(stableKey)

            let mode = CGDisplayCopyDisplayMode(screenNumber)
            let refreshRate = mode?.refreshRate ?? (isBuiltIn ? 120.0 : 60.0)
            let width = Int(screen.frame.width)
            let height = Int(screen.frame.height)
            let resolution = "\(width) × \(height)"
            let scaledW = Int(screen.frame.width * screen.backingScaleFactor)
            let scaledH = Int(screen.frame.height * screen.backingScaleFactor)
            let scaledResolution = "\(scaledW) × \(scaledH)"

            let rawName = screen.localizedName
            let displayName: String
            if !rawName.isEmpty {
                displayName = rawName
            } else if isBuiltIn {
                displayName = "Built-in Display"
            } else {
                displayName = "External Display"
            }

            let roleSuffix = isMain ? (isBuiltIn ? "Main • Built-in" : "Main Display") : "Extended Display"
            let identity = DeviceIdentity(
                stableKey: stableKey,
                kind: .monitor,
                displayName: displayName,
                vendor: isBuiltIn ? "Apple" : "Display",
                model: "\(scaledResolution) @ \(Int(round(refreshRate)))Hz (\(roleSuffix))",
                connectionType: .display,
                resolution: resolution,
                scaledResolution: scaledResolution,
                refreshRate: refreshRate,
                iconName: "display"
            )

            if activeDevices[stableKey] == nil {
                if !isInitialScan && !isBuiltIn {
                    publishEvent(type: .connected, device: identity)
                } else {
                    activeDevices[stableKey] = identity
                }
            } else {
                activeDevices[stableKey] = identity
            }
        }

        // Clean up disconnected displays
        for (key, device) in activeDevices where key.hasPrefix("display_") {
            if !currentDisplayKeys.contains(key) {
                publishEvent(type: .disconnected, device: device)
            }
        }
    }

    // MARK: - 5. Game Controller Monitoring

    private func setupGameControllerMonitoring() {
        NotificationCenter.default.publisher(for: .GCControllerDidConnect)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                guard let controller = notif.object as? GCController else { return }
                self?.handleGameController(controller, isConnected: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                guard let controller = notif.object as? GCController else { return }
                self?.handleGameController(controller, isConnected: false)
            }
            .store(in: &cancellables)

        for controller in GCController.controllers() {
            handleGameController(controller, isConnected: true)
        }
    }

    private func handleGameController(_ controller: GCController, isConnected: Bool) {
        let name = controller.vendorName ?? "Game Controller"
        let stableKey = "gc_\(sanitizeIdentifier(name))_\(controller.playerIndex.rawValue)"

        if !isConnected {
            if let existing = activeDevices[stableKey] {
                publishEvent(type: .disconnected, device: existing)
            }
            return
        }

        let battery = controller.battery.map { Int($0.batteryLevel * 100) }
        let connType: ConnectionType = controller.isSnapshot ? .usb : .bluetooth

        let identity = DeviceIdentity(
            stableKey: stableKey,
            kind: .gameController,
            displayName: name,
            vendor: "Controller",
            model: name,
            connectionType: connType,
            batteryPercentage: battery,
            iconName: "gamecontroller.fill"
        )
        publishEvent(type: .connected, device: identity)
    }

    // MARK: - 6. AirPods Monitoring

    private func setupAirPodsMonitoring() {
        AirPodsService.shared.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                let stableKey = "airpods_current"
                if state.isConnected {
                    let identity = DeviceIdentity(
                        stableKey: stableKey,
                        kind: state.modelName.lowercased().contains("max") ? .headphones : .earbuds,
                        displayName: state.modelName,
                        vendor: "Apple",
                        model: state.modelName,
                        connectionType: .bluetooth,
                        batteryPercentage: state.caseBattery.level ?? state.leftBattery.level,
                        leftBattery: state.leftBattery.level,
                        rightBattery: state.rightBattery.level,
                        caseBattery: state.caseBattery.level,
                        iconName: "airpodspro"
                    )
                    if self.activeDevices[stableKey] == nil {
                        self.publishEvent(type: .connected, device: identity)
                    } else {
                        self.activeDevices[stableKey] = identity
                    }
                } else {
                    if let existing = self.activeDevices[stableKey] {
                        self.publishEvent(type: .disconnected, device: existing)
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Debug Helper

    public func clearEventLog() {
        recentEvents.removeAll()
    }

    public func simulateDeviceEvent(kind: DeviceKind, name: String, isConnected: Bool = true) {
        let stableKey = "sim_\(kind.rawValue)_\(name.lowercased().replacingOccurrences(of: " ", with: "_"))"
        let identity = DeviceIdentity(
            stableKey: stableKey,
            kind: kind,
            displayName: name,
            vendor: kind == .phone ? "Apple" : (kind == .androidPhone ? "Google" : "External"),
            model: name,
            connectionType: .usb,
            capacityBytes: kind == .ssdDrive ? 1_000_000_000_000 : nil,
            freeSpaceBytes: kind == .ssdDrive ? 650_000_000_000 : nil,
            batteryPercentage: nil,
            iconName: kind.defaultIconName
        )
        publishEvent(type: isConnected ? .connected : .disconnected, device: identity)
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

            // Quick Simulation Test Buttons
            HStack(spacing: 8) {
                Button("⚡ Test iPhone") {
                    monitor.simulateDeviceEvent(kind: .phone, name: "iPhone 16 Pro")
                }
                Button("⚡ Test Android") {
                    monitor.simulateDeviceEvent(kind: .androidPhone, name: "Google Pixel 9")
                }
                Button("⚡ Test SSD") {
                    monitor.simulateDeviceEvent(kind: .ssdDrive, name: "Samsung T9 SSD")
                }
                Button("⚡ Test AirPods") {
                    monitor.simulateDeviceEvent(kind: .earbuds, name: "AirPods Pro")
                }
            }
            .controlSize(.small)

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
