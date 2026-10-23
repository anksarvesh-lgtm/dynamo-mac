//
//  BluetoothService.swift
//  boringNotch
//
//  Created for Boring Notch
//

import AppKit
import Combine
import Foundation
import IOBluetooth
import IOKit

public struct DeviceBatteryPart: Identifiable, Hashable, Equatable {
    public enum PartKind: String, Codable, CaseIterable {
        case general = "device"
        case leftEarbud = "left"
        case rightEarbud = "right"
        case caseUnit = "case"

        public var displayName: String {
            switch self {
            case .general:
                return String(localized: "Device")
            case .leftEarbud:
                return String(localized: "Left earbud")
            case .rightEarbud:
                return String(localized: "Right earbud")
            case .caseUnit:
                return String(localized: "Case")
            }
        }
    }

    public var id: String { kind.rawValue }
    public let kind: PartKind
    public let percentage: Int
    public let isCharging: Bool

    public init(kind: PartKind, percentage: Int, isCharging: Bool = false) {
        self.kind = kind
        self.percentage = percentage
        self.isCharging = isCharging
    }
}

public struct BluetoothDeviceInfo: Identifiable, Hashable, Equatable {
    public let id: String // MAC Address
    public let name: String
    public let isConnected: Bool
    public let iconName: String
    public let batteryPercentage: Int? // nil if unavailable - never fake
    public let isCharging: Bool
    public let batteryParts: [DeviceBatteryPart]

    public init(
        id: String,
        name: String,
        isConnected: Bool,
        iconName: String,
        batteryPercentage: Int?,
        isCharging: Bool = false,
        batteryParts: [DeviceBatteryPart] = []
    ) {
        self.id = id
        self.name = name
        self.isConnected = isConnected
        self.iconName = iconName
        self.batteryPercentage = batteryPercentage
        self.isCharging = isCharging
        self.batteryParts = batteryParts
    }

    public var lowestBatteryPercentage: Int? {
        if !batteryParts.isEmpty {
            return batteryParts.map { $0.percentage }.min()
        }
        return batteryPercentage
    }
}

public struct IOBatteryInfo {
    public var overallPercentage: Int?
    public var isCharging: Bool = false
    public var parts: [DeviceBatteryPart] = []

    public init(overallPercentage: Int? = nil, isCharging: Bool = false, parts: [DeviceBatteryPart] = []) {
        self.overallPercentage = overallPercentage
        self.isCharging = isCharging
        self.parts = parts
    }
}

public extension Notification.Name {
    static let bluetoothDeviceDidConnect = Notification.Name("bluetoothDeviceDidConnect")
    static let bluetoothDeviceDidDisconnect = Notification.Name("bluetoothDeviceDidDisconnect")
}

@MainActor
public final class BluetoothService: NSObject, ObservableObject {
    public static let shared = BluetoothService()

    @Published public private(set) var connectedDevices: [BluetoothDeviceInfo] = []
    @Published public private(set) var lastConnectedDeviceName: String = ""

    private var registeredDisconnectDevices = Set<String>()
    private var connectNotification: IOBluetoothUserNotification?
    private var wakeObserver: Any?

    private override init() {
        super.init()
        setupNotificationListeners()
        refreshDevices(notifyAlertManager: false)
    }

    deinit {
        connectNotification?.unregister()
        if let wakeObserver = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    // MARK: - Notification Listeners (No continuous polling)

    private func setupNotificationListeners() {
        // Register for connect notifications
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnectedNotification(_:device:))
        )

        // Refresh devices on system wake from sleep
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshDevices()
            }
        }
    }

    @objc private func deviceConnectedNotification(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        Task { @MainActor in
            let devName = device.nameOrAddress ?? "Bluetooth Device"
            self.lastConnectedDeviceName = devName

            // Show a short popup in the collapsed notch for about 3 seconds
            LiquidViewCoordinator.shared.toggleExpandingView(
                status: true,
                type: .bluetooth,
                value: 1
            )

            NotificationCenter.default.post(name: .bluetoothDeviceDidConnect, object: device)
            self.refreshDevices()
        }
    }

    @objc private func deviceDisconnectedNotification(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        Task { @MainActor in
            if let address = device.addressString {
                self.registeredDisconnectDevices.remove(address)
            }
            NotificationCenter.default.post(name: .bluetoothDeviceDidDisconnect, object: device)
            self.refreshDevices()
        }
    }

    // MARK: - Device Refresh

    public func refreshDevices(notifyAlertManager: Bool = true) {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            self.connectedDevices = []
            if notifyAlertManager {
                BluetoothBatteryAlertManager.shared.evaluateDevices([])
            }
            return
        }

        let batteryMap = queryIORegistryBatteryLevels()
        var connectedList: [BluetoothDeviceInfo] = []

        for device in paired {
            guard device.isConnected() else { continue }

            let address = device.addressString ?? UUID().uuidString
            let name = device.nameOrAddress ?? "Unknown Device"
            let icon = iconForDevice(device, name: name)

            // Look up battery info from IORegistry by normalized address
            let normalizedAddress = address.lowercased().replacingOccurrences(of: ":", with: "-")
            let batteryInfo = batteryMap[normalizedAddress]

            let info = BluetoothDeviceInfo(
                id: address,
                name: name,
                isConnected: true,
                iconName: icon,
                batteryPercentage: batteryInfo?.overallPercentage ?? (batteryInfo?.parts.isEmpty == false ? batteryInfo?.parts.map { $0.percentage }.min() : nil),
                isCharging: batteryInfo?.isCharging ?? false,
                batteryParts: batteryInfo?.parts ?? []
            )
            connectedList.append(info)

            // Register for disconnect notification if not already registered
            if !registeredDisconnectDevices.contains(address) {
                registeredDisconnectDevices.insert(address)
                device.register(
                    forDisconnectNotification: self,
                    selector: #selector(deviceDisconnectedNotification(_:device:))
                )
            }
        }

        self.connectedDevices = connectedList
        if notifyAlertManager {
            BluetoothBatteryAlertManager.shared.evaluateDevices(connectedList)
        }
    }

    // MARK: - IORegistry Battery Lookup

    private func queryIORegistryBatteryLevels() -> [String: IOBatteryInfo] {
        var batteryMap: [String: IOBatteryInfo] = [:]
        let serviceClasses = ["AppleDeviceManagementHIDEventService", "AppleBluetoothHIDDevice", "IOBluetoothHIDDriver"]

        for serviceClass in serviceClasses {
            var iterator: io_iterator_t = 0
            guard let matching = IOServiceMatching(serviceClass) else { continue }

            if IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess {
                while case let service = IOIteratorNext(iterator), service != 0 {
                    defer { IOObjectRelease(service) }
                    var props: Unmanaged<CFMutableDictionary>? = nil
                    if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                       let dict = props?.takeRetainedValue() as? [String: Any] {
                        guard let addr = (dict["DeviceAddress"] as? String) ?? (dict["BluetoothDeviceAddress"] as? String) else { continue }
                        let normalized = addr.lowercased().replacingOccurrences(of: ":", with: "-")

                        var info = batteryMap[normalized] ?? IOBatteryInfo()

                        if let single = (dict["BatteryPercent"] as? Int) ?? (dict["BatteryPercentSingle"] as? Int) ?? (dict["BatteryPercentCombined"] as? Int) {
                            info.overallPercentage = single
                        }

                        let left = dict["BatteryPercentLeft"] as? Int
                        let right = dict["BatteryPercentRight"] as? Int
                        let caseBat = dict["BatteryPercentCase"] as? Int

                        let isChargingGeneral = (dict["IsCharging"] as? Bool) ??
                            ((dict["BatteryChargingStatus"] as? Int).map { $0 != 0 } ??
                            ((dict["BatteryChargingStatusSingle"] as? Int).map { $0 != 0 } ?? false))

                        let leftCharging = (dict["BatteryPercentLeftCharging"] as? Bool) ??
                            ((dict["BatteryPercentLeftCharging"] as? Int).map { $0 != 0 } ?? isChargingGeneral)

                        let rightCharging = (dict["BatteryPercentRightCharging"] as? Bool) ??
                            ((dict["BatteryPercentRightCharging"] as? Int).map { $0 != 0 } ?? isChargingGeneral)

                        let caseCharging = (dict["BatteryPercentCaseCharging"] as? Bool) ??
                            ((dict["BatteryPercentCaseCharging"] as? Int).map { $0 != 0 } ?? isChargingGeneral)

                        var parts: [DeviceBatteryPart] = []
                        if let l = left {
                            parts.append(DeviceBatteryPart(kind: .leftEarbud, percentage: l, isCharging: leftCharging))
                        }
                        if let r = right {
                            parts.append(DeviceBatteryPart(kind: .rightEarbud, percentage: r, isCharging: rightCharging))
                        }
                        if let c = caseBat {
                            parts.append(DeviceBatteryPart(kind: .caseUnit, percentage: c, isCharging: caseCharging))
                        }

                        if !parts.isEmpty {
                            info.parts = parts
                        }

                        info.isCharging = isChargingGeneral || parts.contains(where: { $0.isCharging })
                        batteryMap[normalized] = info
                    }
                }
                IOObjectRelease(iterator)
            }
        }

        return batteryMap
    }

    // MARK: - Device Glyph Classification

    private func iconForDevice(_ device: IOBluetoothDevice, name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("airpod") {
            if lower.contains("max") { return "headphones" }
            return "airpodspro"
        } else if lower.contains("buds") || lower.contains("headphone") || lower.contains("wh-1000") {
            return "headphones"
        } else if lower.contains("mouse") {
            return "magicmouse"
        } else if lower.contains("trackpad") {
            return "trackpad"
        } else if lower.contains("keyboard") {
            return "keyboard"
        } else if lower.contains("watch") {
            return "applewatch"
        } else if lower.contains("controller") || lower.contains("dualsense") || lower.contains("xbox") {
            return "gamecontroller"
        }

        // Major class mapping
        switch device.deviceClassMajor {
        case 0x04: // Audio
            return "headphones"
        case 0x05: // Peripheral
            let minor = device.deviceClassMinor
            if (minor & 0x40) != 0 { return "keyboard" }
            if (minor & 0x80) != 0 { return "magicmouse" }
            return "computermouse"
        case 0x01: // Computer
            return "laptopcomputer"
        case 0x02: // Phone
            return "iphone"
        default:
            return "dot.radiowaves.left.and.right"
        }
    }
}
