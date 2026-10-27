//
//  ChargingIntelligenceService.swift
//  LiquidDynamo
//
//  Detects MagSafe vs USB-C charging, exact hardware ports, wattages, and coordinates
//  connected device representation and liquid status indications.
//

import AppKit
import Combine
import Foundation
import IOKit
import IOKit.ps
import SwiftUI

public enum ChargingMethod: String, Codable {
    case magSafe = "MagSafe"
    case usbC = "USB-C"
    case battery = "Battery"
}

@MainActor
public final class ChargingIntelligenceService: ObservableObject {
    public static let shared = ChargingIntelligenceService()

    @Published public private(set) var chargingMethod: ChargingMethod = .battery
    @Published public private(set) var isPluggedIn: Bool = false
    @Published public private(set) var isCharging: Bool = false
    @Published public private(set) var adapterWatts: Int = 0
    @Published public private(set) var adapterName: String = ""
    @Published public private(set) var adapterDescription: String = ""
    @Published public private(set) var adapterFamily: String = ""
    @Published public private(set) var connectedPortDescription: String = "USB-C Port"
    @Published public private(set) var activePortIndex: Int = 0
    @Published public private(set) var inputPowerWatts: Double = 0.0
    @Published public private(set) var voltageVolts: Double = 0.0
    @Published public private(set) var currentAmperes: Double = 0.0
    @Published public private(set) var batteryLevel: Int = 100
    @Published public private(set) var timeToFullMinutes: Int? = nil
    @Published public private(set) var chargingStatusText: String = "On AC Power"
    @Published public private(set) var showTransientChargingRipple: Bool = false
    @Published public private(set) var currentChargerIdentity: DeviceIdentity? = nil

    private var previousWasConnected: Bool = false
    private var pollTimer: Timer?

    private init() {
        DispatchQueue.main.async { [weak self] in
            self?.start()
        }
    }

    private var runLoopSource: CFRunLoopSource?

    public func start() {
        stop()
        checkChargingStatus()

        // 1. Native event-driven IOKit Power Sources runloop source (instant, zero polling)
        if runLoopSource == nil {
            if let source = IOPSNotificationCreateRunLoopSource({ context in
                guard let context = context else { return }
                let service = Unmanaged<ChargingIntelligenceService>.fromOpaque(context).takeUnretainedValue()
                Task { @MainActor in
                    service.checkChargingStatus()
                }
            }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue() {
                self.runLoopSource = source
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }

        // 2. Slow fallback timer with generous tolerance (30s interval, 10s tolerance)
        let timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkChargingStatus()
            }
        }
        timer.tolerance = 10.0
        pollTimer = timer
    }

    public func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
    }

    public func checkChargingStatus() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return
        }

        var isACConnected = false
        var isCurrentlyCharging = false
        var curBatLevel = 100

        for source in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] {
                if let powerSource = desc[kIOPSPowerSourceStateKey] as? String, powerSource == kIOPSACPowerValue {
                    isACConnected = true
                }
                if let charging = desc["Is Charging"] as? Bool, charging {
                    isCurrentlyCharging = true
                }
                if let cap = desc[kIOPSCurrentCapacityKey] as? Int {
                    curBatLevel = cap
                }
            }
        }

        self.isPluggedIn = isACConnected
        self.batteryLevel = curBatLevel

        if isACConnected {
            var method: ChargingMethod = .usbC
            var watts: Int = 0
            var descText: String = "USB-C Charger"
            var familyCodeText: String = ""

            if let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
                if let w = adapter["Watts"] as? Int {
                    watts = w
                }
                if let desc = adapter["Description"] as? String {
                    descText = desc
                    let lower = desc.lowercased()
                    if lower.contains("magsafe") {
                        method = .magSafe
                    } else if lower.contains("pd") || lower.contains("usb") {
                        method = .usbC
                    }
                }
                if let family = adapter["FamilyCode"] as? Int {
                    let uFamily = UInt32(bitPattern: Int32(truncatingIfNeeded: family))
                    familyCodeText = String(format: "0x%08x", uFamily)
                    // Apple MagSafe 3 on Apple Silicon uses 0xe0004000...0xe00040ff (e.g. 0xe000400a)
                    if (uFamily & 0xffffff00) == 0xe0004000 || (uFamily & 0xffff0000) == 0xe0000000 {
                        method = .magSafe
                    }
                }
            }

            self.chargingMethod = method
            self.adapterWatts = watts
            self.adapterDescription = descText
            self.adapterFamily = familyCodeText

            // Deep Hardware Port & Power Distribution Query via AppleSmartBattery
            let hwInfo = queryAppleSmartBatteryPortAndPower(method: method)
            self.connectedPortDescription = hwInfo.portDescription
            self.activePortIndex = hwInfo.portIndex
            self.inputPowerWatts = hwInfo.inputPowerW > 0 ? hwInfo.inputPowerW : Double(watts)
            self.voltageVolts = hwInfo.voltageV
            self.currentAmperes = hwInfo.currentA
            self.timeToFullMinutes = hwInfo.timeToFull
            if hwInfo.batteryLevel > 0 {
                self.batteryLevel = hwInfo.batteryLevel
            }

            if isCurrentlyCharging || hwInfo.isCharging {
                self.isCharging = true
                if let mins = hwInfo.timeToFull {
                    if mins >= 60 {
                        self.chargingStatusText = "Charging (\(mins / 60)h \(mins % 60)m to full)"
                    } else {
                        self.chargingStatusText = "Charging (\(mins)m to full)"
                    }
                } else {
                    self.chargingStatusText = "Fast Charging"
                }
            } else {
                self.isCharging = false
                if self.batteryLevel >= 100 {
                    self.chargingStatusText = "Fully Charged • On AC Power"
                } else if hwInfo.notChargingReason == 16777216 {
                    self.chargingStatusText = "Connected • Optimized Battery (Hold)"
                } else {
                    self.chargingStatusText = "Connected • On AC Power"
                }
            }

            // Publish Charger as a real connected device into DeviceMonitor
            updateChargerDeviceIdentity()

            // Detect freshly plugged in transition
            if !previousWasConnected {
                triggerTransientChargingRipple()
            }
            previousWasConnected = true
        } else {
            self.chargingMethod = .battery
            self.adapterWatts = 0
            self.isCharging = false
            self.inputPowerWatts = 0.0
            self.voltageVolts = 0.0
            self.currentAmperes = 0.0
            self.timeToFullMinutes = nil
            self.chargingStatusText = "On Battery Power"
            self.currentChargerIdentity = nil
            previousWasConnected = false
        }
    }

    private func queryAppleSmartBatteryPortAndPower(method: ChargingMethod) -> (
        portDescription: String,
        portIndex: Int,
        inputPowerW: Double,
        voltageV: Double,
        currentA: Double,
        isCharging: Bool,
        notChargingReason: Int,
        timeToFull: Int?,
        batteryLevel: Int
    ) {
        let match = IOServiceMatching("AppleSmartBattery")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, match)
        guard service != 0 else {
            return ("USB-C Port", 0, 0, 0, 0, false, 0, nil, 100)
        }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return ("USB-C Port", 0, 0, 0, 0, false, 0, nil, 100)
        }

        var activeIndex = 0
        var foundActivePort = false

        if let portInfo = dict["PortControllerInfo"] as? [[String: Any]] {
            for (idx, p) in portInfo.enumerated() {
                let loser = p["PortControllerLoserReason"] as? Int ?? -1
                let rdo = p["PortControllerActiveContractRdo"] as? Int ?? 0
                let maxP = p["PortControllerMaxPower"] as? Int ?? 0
                if loser == 0 || (rdo != 0 && maxP > 0) {
                    activeIndex = idx
                    foundActivePort = true
                    break
                }
            }
        }

        // Format user-facing physical port location
        let portDesc: String
        if method == .magSafe {
            portDesc = "MagSafe 3 Port (Left Side)"
        } else {
            switch activeIndex {
            case 0:
                portDesc = "USB-C Port 1 (Left Side)"
            case 1:
                portDesc = "USB-C Port 1 (Left Side)"
            case 2:
                portDesc = "USB-C Port 2 (Left Side)"
            case 3:
                portDesc = "USB-C Port (Right Side)"
            default:
                portDesc = "USB-C / Thunderbolt Port \(activeIndex + 1)"
            }
        }

        var powerW: Double = 0.0
        var voltV: Double = 0.0
        var currA: Double = 0.0

        if let powerDist = dict["PowerDistribution"] as? [String: Any] {
            if let mw = powerDist["IPDInputPower"] as? Double {
                powerW = mw / 1000.0
            } else if let mw = powerDist["IPDInputPower"] as? Int {
                powerW = Double(mw) / 1000.0
            }
            if let mv = powerDist["IPDInputVoltage"] as? Double {
                voltV = mv / 1000.0
            } else if let mv = powerDist["IPDInputVoltage"] as? Int {
                voltV = Double(mv) / 1000.0
            }
            if let ma = powerDist["IPDInputCurrent"] as? Double {
                currA = ma / 1000.0
            } else if let ma = powerDist["IPDInputCurrent"] as? Int {
                currA = Double(ma) / 1000.0
            }
        }

        if let adapterDetails = dict["AdapterDetails"] as? [String: Any] {
            if voltV == 0, let mv = adapterDetails["AdapterVoltage"] as? Int {
                voltV = Double(mv) / 1000.0
            }
            if currA == 0, let ma = adapterDetails["Current"] as? Int {
                currA = Double(ma) / 1000.0
            }
            if powerW == 0, voltV > 0, currA > 0 {
                powerW = voltV * currA
            }
        }

        var isActivelyCharging = false
        var notChargingReason = 0
        if let chargerData = dict["ChargerData"] as? [String: Any] {
            isActivelyCharging = (chargerData["IsCharging"] as? Int ?? 0) == 1 || (chargerData["IsCharging"] as? Bool ?? false)
            notChargingReason = chargerData["NotChargingReason"] as? Int ?? 0
        }

        let curCap = (dict["CurrentCapacity"] as? Int) ?? (dict["StateOfCharge"] as? Int) ?? 100
        let timeRemaining = dict["AvgTimeToFull"] as? Int
        let validTimeToFull = (timeRemaining != nil && timeRemaining! < 60000 && timeRemaining! > 0) ? timeRemaining : nil

        return (portDesc, activeIndex, powerW, voltV, currA, isActivelyCharging, notChargingReason, validTimeToFull, curCap)
    }

    private func updateChargerDeviceIdentity() {
        guard isPluggedIn else {
            currentChargerIdentity = nil
            return
        }

        let name: String
        let vendor: String
        if chargingMethod == .magSafe {
            name = adapterWatts > 0 ? "MagSafe 3 Charger (\(adapterWatts)W)" : "Apple MagSafe 3 Charger"
            vendor = "Apple"
        } else {
            if !adapterDescription.isEmpty && adapterDescription.lowercased() != "pd charger" {
                name = adapterDescription
            } else if adapterWatts > 0 {
                name = "\(adapterWatts)W USB-C Power Adapter"
            } else {
                name = "USB-C Power Adapter"
            }
            vendor = adapterDescription.lowercased().contains("apple") ? "Apple" : "USB-PD"
        }

        let modelStr = adapterWatts > 0 ? "\(adapterWatts)W Power Delivery" : "AC Power Adapter"

        let identity = DeviceIdentity(
            stableKey: "power_adapter",
            kind: .charger,
            displayName: name,
            vendor: vendor,
            model: modelStr,
            connectionType: .power,
            batteryPercentage: batteryLevel,
            iconName: chargingMethod == .magSafe ? "bolt.shield.fill" : "powerplug.fill",
            chargerWatts: adapterWatts > 0 ? adapterWatts : Int(round(inputPowerWatts)),
            chargerPort: connectedPortDescription,
            isChargingState: isCharging,
            chargingVoltage: voltageVolts,
            chargingCurrent: currentAmperes,
            chargingPowerWatts: inputPowerWatts > 0 ? inputPowerWatts : Double(adapterWatts),
            chargingStatusDescription: chargingStatusText,
            chargingMethodType: chargingMethod.rawValue
        )

        self.currentChargerIdentity = identity
    }

    private func triggerTransientChargingRipple() {
        showTransientChargingRipple = true
        let adapterName = chargingMethod == .magSafe ? "MagSafe (\(adapterWatts)W)" : (adapterWatts > 0 ? "USB-C (\(adapterWatts)W)" : "Power Connected")
        let batteryPct = Double(batteryLevel) / 100.0
        let payload = AlertPayload(
            id: "power.charging.transient",
            kind: .chargingConnected(level: batteryPct),
            title: chargingMethod == .magSafe ? "MagSafe Connected" : "Charger Connected",
            subtitle: "\(adapterName) • \(batteryLevel)%",
            iconName: chargingMethod == .magSafe ? "bolt.shield.fill" : "bolt.fill",
            iconColor: .green,
            dwellDuration: 3.5,
            progress: batteryPct
        )
        IslandController.shared.showAlert(payload: payload)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            withAnimation(.easeOut(duration: 0.8)) {
                self?.showTransientChargingRipple = false
            }
        }
    }
}
