//
//  AirPodsBackend.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import AppKit
import CoreBluetooth
import CoreMotion
import Foundation
import IOBluetooth
import IOKit

// MARK: - Backend Protocol

@MainActor
public protocol AirPodsBackendDelegate: AnyObject {
    func backendDidUpdateSystemInfo(
        isConnected: Bool,
        deviceID: String?,
        modelName: String,
        capabilities: AirPodsCapabilities,
        baselineBattery: Int?
    )
    func backendDidUpdateBLEStatus(
        leftBattery: Int?,
        rightBattery: Int?,
        caseBattery: Int?,
        leftCharging: Bool,
        rightCharging: Bool,
        caseCharging: Bool,
        leftInEar: Bool?,
        rightInEar: Bool?,
        lidOpen: Bool?
    )
    func backendDidUpdateHeadMotion(roll: Double, pitch: Double, yaw: Double)
}

@MainActor
public protocol AirPodsBackend: AnyObject {
    var isRunning: Bool { get }
    func start()
    func stop()
}

// MARK: - 1. System Data Backend (IOBluetooth & IORegistry)

@MainActor
public final class SystemDataBackend: NSObject, AirPodsBackend {
    public weak var delegate: AirPodsBackendDelegate?
    public private(set) var isRunning: Bool = false

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotification: IOBluetoothUserNotification?
    private var connectedDevice: IOBluetoothDevice?

    public override init() {
        super.init()
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        registerConnectionNotification()
        checkConnectedDevices()
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotification?.unregister()
        disconnectNotification = nil
        connectedDevice = nil
    }

    private func registerConnectionNotification() {
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnectedNotification(_:device:))
        )
    }

    @objc private func deviceConnectedNotification(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        checkConnectedDevices()
    }

    @objc private func deviceDisconnectedNotification(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        checkConnectedDevices()
    }

    public func checkConnectedDevices() {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }

        var foundAirPods: IOBluetoothDevice? = nil
        var modelID: UInt16 = 0x2002 // Default fallback
        var detectedName = "AirPods"

        for device in paired where device.isConnected() {
            let name = device.nameOrAddress ?? ""
            let lower = name.lowercased()
            if lower.contains("airpods") || lower.contains("beats") {
                foundAirPods = device
                detectedName = name

                if lower.contains("pro") {
                    modelID = lower.contains("2") ? 0x2014 : 0x200E
                } else if lower.contains("max") {
                    modelID = 0x200A
                } else if lower.contains("3") {
                    modelID = 0x2013
                } else if lower.contains("4") {
                    modelID = 0x2018
                } else {
                    modelID = 0x200F // 2nd gen
                }
                break
            }
        }

        if let device = foundAirPods {
            self.connectedDevice = device
            let address = device.addressString ?? ""
            let normalized = address.lowercased().replacingOccurrences(of: ":", with: "-")
            let capabilities = AirPodsCapabilities.forModel(modelID: modelID)
            let batteryLevel = queryIORegistryBattery(for: normalized)

            // Register for disconnect notification
            disconnectNotification?.unregister()
            disconnectNotification = device.register(
                forDisconnectNotification: self,
                selector: #selector(deviceDisconnectedNotification(_:device:))
            )

            delegate?.backendDidUpdateSystemInfo(
                isConnected: true,
                deviceID: address,
                modelName: detectedName,
                capabilities: capabilities,
                baselineBattery: batteryLevel
            )
        } else {
            self.connectedDevice = nil
            disconnectNotification?.unregister()
            disconnectNotification = nil
            delegate?.backendDidUpdateSystemInfo(
                isConnected: false,
                deviceID: nil,
                modelName: "AirPods",
                capabilities: .none,
                baselineBattery: nil
            )
        }
    }

    private func queryIORegistryBattery(for normalizedAddress: String) -> Int? {
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
                        let entryNorm = addr.lowercased().replacingOccurrences(of: ":", with: "-")
                        if entryNorm == normalizedAddress {
                            if let single = (dict["BatteryPercent"] as? Int) ?? (dict["BatteryPercentSingle"] as? Int) ?? (dict["BatteryPercentCombined"] as? Int) {
                                return single
                            }
                        }
                    }
                }
            }
        }
        return nil
    }
}

// MARK: - 2. BLE Advertisement Backend (0x004C Type 0x07 Proximity Frames)

public final class BLEAdvertisementBackend: NSObject, AirPodsBackend, CBCentralManagerDelegate {
    @MainActor public weak var delegate: AirPodsBackendDelegate?
    @MainActor public private(set) var isRunning: Bool = false

    private var centralManager: CBCentralManager?
    private var targetDeviceAddress: String?

    @MainActor
    public func setTargetDeviceAddress(_ address: String?) {
        self.targetDeviceAddress = address?.lowercased().replacingOccurrences(of: "-", with: ":")
    }

    @MainActor
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: .main)
        } else if centralManager?.state == .poweredOn {
            startScanning()
        }
    }

    @MainActor
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        centralManager?.stopScan()
    }

    @MainActor
    private func startScanning() {
        guard isRunning, centralManager?.state == .poweredOn else { return }
        centralManager?.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    // CBCentralManagerDelegate
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state == .poweredOn && self.isRunning {
                self.startScanning()
            }
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        guard let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else { return }
        guard mfgData.count >= 9 else { return }
        guard mfgData[0] == 0x4C && mfgData[1] == 0x00 else { return }
        guard mfgData[2] == 0x07 else { return }

        Task { @MainActor in
            guard self.isRunning else { return }
            self.parseProximityFrame(mfgData)
        }
    }

    @MainActor
    private func parseProximityFrame(_ data: Data) {
        let rawRight = (data[6] >> 4) & 0x0F
        let rawLeft = data[6] & 0x0F

        let rawCharging = (data[7] >> 4) & 0x0F
        let rawCase = data[7] & 0x0F

        let statusByte = data[8]
        let leftInEar = (statusByte & 0x02) != 0
        let rightInEar = (statusByte & 0x08) != 0
        let lidOpen = (statusByte & 0x04) != 0

        let leftPct: Int? = (rawLeft <= 10) ? Int(rawLeft) * 10 : nil
        let rightPct: Int? = (rawRight <= 10) ? Int(rawRight) * 10 : nil
        let casePct: Int? = (rawCase <= 10) ? Int(rawCase) * 10 : nil

        let leftCharging = (rawCharging & 0x01) != 0
        let rightCharging = (rawCharging & 0x02) != 0
        let caseCharging = (rawCharging & 0x04) != 0

        delegate?.backendDidUpdateBLEStatus(
            leftBattery: leftPct,
            rightBattery: rightPct,
            caseBattery: casePct,
            leftCharging: leftCharging,
            rightCharging: rightCharging,
            caseCharging: caseCharging,
            leftInEar: leftInEar,
            rightInEar: rightInEar,
            lidOpen: lidOpen
        )
    }
}

// MARK: - 3. Head Motion Backend (CMHeadphoneMotionManager)

@MainActor
public final class HeadMotionBackend: AirPodsBackend {
    public weak var delegate: AirPodsBackendDelegate?
    public private(set) var isRunning: Bool = false

    private let motionManager = CMHeadphoneMotionManager()

    public var isMotionAvailable: Bool {
        motionManager.isDeviceMotionAvailable
    }

    public var authorizationStatus: CMAuthorizationStatus {
        CMHeadphoneMotionManager.authorizationStatus()
    }

    public func start() {
        start(onError: { _ in })
    }

    public func start(onError: @escaping (String) -> Void) {
        guard !isRunning else { return }
        guard isMotionAvailable else {
            onError(String(localized: "Headphone motion sensors are not available on this connection."))
            return
        }

        let auth = authorizationStatus
        if auth == .denied || auth == .restricted {
            onError(String(localized: "Motion permission was denied. Please allow Motion access in System Settings."))
            return
        }

        isRunning = true
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self else { return }
            if let error = error {
                self.stop()
                onError(error.localizedDescription)
                return
            }
            guard let motion = motion else { return }
            let attitude = motion.attitude
            self.delegate?.backendDidUpdateHeadMotion(
                roll: attitude.roll,
                pitch: attitude.pitch,
                yaw: attitude.yaw
            )
        }
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        motionManager.stopDeviceMotionUpdates()
    }
}

// MARK: - 4. AAP Backend (Apple Accessory Protocol over L2CAP PSM 0x1001)

@MainActor
public final class AAPBackend: AirPodsBackend {
    public private(set) var isRunning: Bool = false
    public private(set) var isChannelOpen: Bool = false

    public func start() {
        guard !isRunning else { return }
        isRunning = true
    }

    public func stop() {
        isRunning = false
        isChannelOpen = false
    }

    public func executeCommand(_ command: AirPodsCommand) async -> Result<Void, AirPodsControlError> {
        return .failure(.aapUnavailable(
            String(localized: "Direct accessory control is restricted by macOS. Please open Sound settings.")
        ))
    }
}
