//
//  MultiDisplayBrightnessService.swift
//  boringNotch
//
//  Created for Boring Notch
//

import AppKit
import Combine
import CoreGraphics
import Foundation
import IOKit

public enum BrightnessControlMethod: String, CaseIterable {
    case builtIn = "Built-in"
    case ddcHardware = "DDC/CI Hardware"
    case softwareDimming = "software dimming"
    case none = "Unsupported"
}

public final class ManagedDisplay: Identifiable, ObservableObject {
    public let id: CGDirectDisplayID
    public let name: String
    public let isBuiltIn: Bool

    @Published public var brightness: Float = 1.0 // 0.0 to 1.0
    @Published public var controlMethod: BrightnessControlMethod = .builtIn
    @Published public var isControllable: Bool = true

    public init(id: CGDirectDisplayID, name: String, isBuiltIn: Bool, brightness: Float, controlMethod: BrightnessControlMethod) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.brightness = brightness
        self.controlMethod = controlMethod
        self.isControllable = controlMethod != .none
    }
}

@MainActor
public final class MultiDisplayBrightnessService: ObservableObject {
    public static let shared = MultiDisplayBrightnessService()

    @Published public private(set) var displays: [ManagedDisplay] = []

    // Background queue for I2C / DDC communication and gamma calculations
    private let ddcQueue = DispatchQueue(label: "com.agrigence.liquiddynamo.ddc", qos: .userInitiated)
    private var pendingDDCWorkItems: [CGDirectDisplayID: DispatchWorkItem] = [:]

    // Function pointers for private DisplayServices SPI
    private typealias DisplayServicesGetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias DisplayServicesSetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private var dsGetBrightness: DisplayServicesGetBrightnessFn?
    private var dsSetBrightness: DisplayServicesSetBrightnessFn?

    // Function pointers for IOAVService DDC
    private typealias IOAVServiceRef = UnsafeMutableRawPointer
    private typealias IOAVServiceCreateFn = @convention(c) (CFAllocator?) -> IOAVServiceRef?
    private typealias IOAVServiceWriteI2CFn = @convention(c) (IOAVServiceRef, UInt32, UInt32, UnsafeMutablePointer<UInt8>, UInt32) -> IOReturn
    private typealias IOAVServiceReadI2CFn = @convention(c) (IOAVServiceRef, UInt32, UInt32, UnsafeMutablePointer<UInt8>, UInt32) -> IOReturn
    private var ioavCreate: IOAVServiceCreateFn?
    private var ioavWriteI2C: IOAVServiceWriteI2CFn?
    private var ioavReadI2C: IOAVServiceReadI2CFn?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        loadPrivateSymbols()
        refreshDisplays()
        setupNotificationObservers()
    }

    deinit {
        // Restore standard display gamma calibration upon deallocation
        CGDisplayRestoreColorSyncSettings()
    }

    // MARK: - Symbol Loading (with graceful fallbacks)

    private func loadPrivateSymbols() {
        // Load DisplayServices
        let displayServicesPaths = [
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/Current/DisplayServices"
        ]
        for path in displayServicesPaths {
            if let handle = dlopen(path, RTLD_LAZY) {
                if let getSym = dlsym(handle, "DisplayServicesGetBrightness") {
                    dsGetBrightness = unsafeBitCast(getSym, to: DisplayServicesGetBrightnessFn.self)
                }
                if let setSym = dlsym(handle, "DisplayServicesSetBrightness") {
                    dsSetBrightness = unsafeBitCast(setSym, to: DisplayServicesSetBrightnessFn.self)
                }
                break
            }
        }

        // Load IOAVService from SkyLight / system frameworks
        let skyLightPaths = [
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/Current/SkyLight"
        ]
        for path in skyLightPaths {
            if let handle = dlopen(path, RTLD_LAZY) {
                if let createSym = dlsym(handle, "IOAVServiceCreate") {
                    ioavCreate = unsafeBitCast(createSym, to: IOAVServiceCreateFn.self)
                }
                if let writeSym = dlsym(handle, "IOAVServiceWriteI2C") {
                    ioavWriteI2C = unsafeBitCast(writeSym, to: IOAVServiceWriteI2CFn.self)
                }
                if let readSym = dlsym(handle, "IOAVServiceReadI2C") {
                    ioavReadI2C = unsafeBitCast(readSym, to: IOAVServiceReadI2CFn.self)
                }
                break
            }
        }
    }

    // MARK: - Notifications

    private func setupNotificationObservers() {
        // Refresh when monitors are connected or disconnected
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // Restore gamma on parameter changes to avoid persistent color distortion
                CGDisplayRestoreColorSyncSettings()
                self?.refreshDisplays()
            }
            .store(in: &cancellables)

        // Restore normal gamma when application quits
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .receive(on: RunLoop.main)
            .sink { _ in
                CGDisplayRestoreColorSyncSettings()
            }
            .store(in: &cancellables)

        // Restore gamma on sleep so waking doesn't inherit skewed color tables
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: RunLoop.main)
            .sink { _ in
                CGDisplayRestoreColorSyncSettings()
            }
            .store(in: &cancellables)

        // Refresh displays on wake
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshDisplays()
            }
            .store(in: &cancellables)
    }

    // MARK: - Display Enumeration

    public func refreshDisplays() {
        var managedList: [ManagedDisplay] = []

        for screen in NSScreen.screens {
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            let displayID = CGDirectDisplayID(screenNumber.uint32Value)
            let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
            let name = screen.localizedName

            if isBuiltIn {
                // Built-in display
                var brightness: Float = 1.0
                if let fn = dsGetBrightness {
                    var val: Float = 0
                    if fn(displayID, &val) == 0 {
                        brightness = val
                    }
                }
                let display = ManagedDisplay(
                    id: displayID,
                    name: name,
                    isBuiltIn: true,
                    brightness: brightness,
                    controlMethod: dsSetBrightness != nil ? .builtIn : .none
                )
                managedList.append(display)
            } else {
                // External display: attempt DDC/CI or fallback to software dimming
                let hasDDC = ioavWriteI2C != nil && ioavCreate != nil
                let method: BrightnessControlMethod = hasDDC ? .ddcHardware : .softwareDimming
                let display = ManagedDisplay(
                    id: displayID,
                    name: name,
                    isBuiltIn: false,
                    brightness: 1.0,
                    controlMethod: method
                )
                managedList.append(display)
            }
        }

        self.displays = managedList
    }

    // MARK: - Brightness Adjustment API

    public func setBrightness(_ value: Float, for display: ManagedDisplay) {
        let clamped = max(0.0, min(1.0, value))
        display.brightness = clamped

        switch display.controlMethod {
        case .builtIn:
            setBuiltInBrightness(clamped, for: display.id)

        case .ddcHardware:
            setDDCHardwareBrightness(clamped, for: display)

        case .softwareDimming:
            setSoftwareDimming(clamped, for: display.id)

        case .none:
            break
        }
    }

    // MARK: - Built-in Display Control

    private func setBuiltInBrightness(_ value: Float, for displayID: CGDirectDisplayID) {
        if let fn = dsSetBrightness {
            _ = fn(displayID, value)
        }
        // Also update system BrightnessManager if this is the main screen
        if displayID == CGMainDisplayID() {
            BrightnessManager.shared.refresh()
        }
    }

    // MARK: - DDC/CI Hardware Control (Rate-Limited Off Main Thread)

    private func setDDCHardwareBrightness(_ value: Float, for display: ManagedDisplay) {
        // Cancel pending debounced DDC write for this display if user is rapidly sliding
        pendingDDCWorkItems[display.id]?.cancel()

        let workItem = DispatchWorkItem { [weak self, weak display] in
            guard let self = self, let display = display else { return }

            let success = self.performDDCWrite(brightness: value, displayID: display.id)
            if !success {
                // If DDC write fails (e.g. monitor does not accept DDC commands), seamlessly fall back to software dimming
                Task { @MainActor in
                    display.controlMethod = .softwareDimming
                    self.setSoftwareDimming(value, for: display.id)
                }
            }
        }

        pendingDDCWorkItems[display.id] = workItem
        // Rate-limit I2C transmissions to 40ms intervals to prevent I2C bus congestion
        ddcQueue.asyncAfter(deadline: .now() + .milliseconds(40), execute: workItem)
    }

    private func performDDCWrite(brightness: Float, displayID: CGDirectDisplayID) -> Bool {
        guard let createFn = ioavCreate, let writeFn = ioavWriteI2C else { return false }
        guard let service = createFn(kCFAllocatorDefault) else { return false }

        // Standard DDC/CI VCP opcode 0x10 is Brightness
        // DDC packet: [length (0x84), 0x03, 0x10, highByte, lowByte, checksum]
        let intVal = UInt16(min(max(brightness * 100.0, 0), 100))
        let highByte = UInt8((intVal >> 8) & 0xFF)
        let lowByte = UInt8(intVal & 0xFF)

        var packet: [UInt8] = [
            0x51, // Source address
            0x84, // Length (4 data bytes: 0x03 + 0x10 + high + low)
            0x03, // Set VCP feature opcode
            0x10, // VCP Feature: Brightness
            highByte,
            lowByte,
            0x00  // Checksum placeholder
        ]

        // Compute XOR checksum: 0x6E (destination DDC address) ^ byte[0] ^ ... ^ byte[5]
        var checksum: UInt8 = 0x6E
        for i in 0..<6 {
            checksum ^= packet[i]
        }
        packet[6] = checksum

        let status = writeFn(service, 0x37, 0x51, &packet, UInt32(packet.count))
        return status == kIOReturnSuccess
    }

    // MARK: - Software Dimming Fallback (Gamma Table)

    private func setSoftwareDimming(_ value: Float, for displayID: CGDirectDisplayID) {
        ddcQueue.async {
            let tableSize: UInt32 = 256
            var red = [CGGammaValue](repeating: 0, count: Int(tableSize))
            var green = [CGGammaValue](repeating: 0, count: Int(tableSize))
            var blue = [CGGammaValue](repeating: 0, count: Int(tableSize))

            // Keep a minimum floor so the screen doesn't become completely pitch black
            let factor = max(0.05, Double(value))

            for i in 0..<Int(tableSize) {
                let gamma = CGGammaValue((Double(i) / Double(tableSize - 1)) * factor)
                red[i] = gamma
                green[i] = gamma
                blue[i] = gamma
            }

            _ = CGSetDisplayTransferByTable(displayID, tableSize, red, green, blue)
        }
    }
}
