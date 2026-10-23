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

    public var hasExternalControllableDisplay: Bool {
        displays.contains { !$0.isBuiltIn && $0.isControllable }
    }

    public var externalDisplays: [ManagedDisplay] {
        displays.filter { !$0.isBuiltIn }
    }

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

        let currentIDs = Set(managedList.map { $0.id })
        for old in self.displays where !currentIDs.contains(old.id) {
            DisplayDimmingOverlayManager.shared.removeOverlay(for: old.id)
        }

        // Preserve current brightness state if display was already present
        for display in managedList {
            if let existing = self.displays.first(where: { $0.id == display.id }) {
                display.brightness = existing.brightness
            }
        }

        self.displays = managedList
    }

    // MARK: - Display Dimming Overlay Management

    public func setBrightness(_ value: Float, for display: ManagedDisplay) {
        let clamped = max(0.0, min(1.0, value))
        display.brightness = clamped

        if display.isBuiltIn {
            // Built-in screen: native SPI
            if let fn = dsSetBrightness {
                _ = fn(display.id, clamped)
            }
            if display.id == CGMainDisplayID() {
                BrightnessManager.shared.refresh()
            }
            return
        }

        // External Display:
        // 1. Try hardware SPI (Apple Studio Display, Pro Display XDR, etc.)
        if let fn = dsSetBrightness, fn(display.id, clamped) == 0 {
            display.controlMethod = .ddcHardware
            DisplayDimmingOverlayManager.shared.removeOverlay(for: display.id)
            return
        }

        // 2. Hardware DDC write if available
        if display.controlMethod == .ddcHardware {
            setDDCHardwareBrightness(clamped, for: display)
            return
        }

        // 3. Guaranteed software-level dimming (works on 100% of external and virtual displays)
        display.controlMethod = .softwareDimming
        setSoftwareDimming(clamped, for: display.id)
    }

    // MARK: - DDC/CI Hardware Control (Rate-Limited Off Main Thread)

    private func setDDCHardwareBrightness(_ value: Float, for display: ManagedDisplay) {
        pendingDDCWorkItems[display.id]?.cancel()

        let workItem = DispatchWorkItem { [weak self, weak display] in
            guard let self = self, let display = display else { return }

            let success = self.performDDCWrite(brightness: value, displayID: display.id)
            if !success {
                Task { @MainActor in
                    display.controlMethod = .softwareDimming
                    self.setSoftwareDimming(value, for: display.id)
                }
            }
        }

        pendingDDCWorkItems[display.id] = workItem
        ddcQueue.asyncAfter(deadline: .now() + .milliseconds(40), execute: workItem)
    }

    private func performDDCWrite(brightness: Float, displayID: CGDirectDisplayID) -> Bool {
        guard let createFn = ioavCreate, let writeFn = ioavWriteI2C else { return false }
        guard let service = createFn(kCFAllocatorDefault) else { return false }

        let intVal = UInt16(min(max(brightness * 100.0, 0), 100))
        let highByte = UInt8((intVal >> 8) & 0xFF)
        let lowByte = UInt8(intVal & 0xFF)

        var packet: [UInt8] = [
            0x51,
            0x84,
            0x03,
            0x10,
            highByte,
            lowByte,
            0x00
        ]

        var checksum: UInt8 = 0x6E
        for i in 0..<6 {
            checksum ^= packet[i]
        }
        packet[6] = checksum

        let status = writeFn(service, 0x37, 0x51, &packet, UInt32(packet.count))
        return status == kIOReturnSuccess
    }

    // MARK: - Software Dimming (Overlay + Gamma Fallback)

    private var pendingDimmingWorkItems: [CGDirectDisplayID: DispatchWorkItem] = [:]

    private func setSoftwareDimming(_ value: Float, for displayID: CGDirectDisplayID) {
        // Apply hardware-accelerated pass-through black overlay on main thread
        DisplayDimmingOverlayManager.shared.setDimming(brightness: value, for: displayID)

        // Also update gamma table on background queue for additional depth if supported
        pendingDimmingWorkItems[displayID]?.cancel()
        let workItem = DispatchWorkItem {
            let tableSize: UInt32 = 256
            var red = [CGGammaValue](repeating: 0, count: Int(tableSize))
            var green = [CGGammaValue](repeating: 0, count: Int(tableSize))
            var blue = [CGGammaValue](repeating: 0, count: Int(tableSize))

            let factor = max(0.04, Double(value))
            for i in 0..<Int(tableSize) {
                let gamma = CGGammaValue((Double(i) / Double(tableSize - 1)) * factor)
                red[i] = gamma
                green[i] = gamma
                blue[i] = gamma
            }

            _ = CGSetDisplayTransferByTable(displayID, tableSize, red, green, blue)
        }

        pendingDimmingWorkItems[displayID] = workItem
        ddcQueue.async(execute: workItem)
    }
}

// MARK: - Display Dimming Overlay Window & Manager

@MainActor
public final class DisplayDimmingOverlayManager {
    public static let shared = DisplayDimmingOverlayManager()

    private var overlayWindows: [CGDirectDisplayID: DisplayDimmingOverlayWindow] = [:]

    private init() {}

    public func setDimming(brightness: Float, for displayID: CGDirectDisplayID) {
        guard let screen = NSScreen.screens.first(where: {
            if let num = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                return CGDirectDisplayID(num.uint32Value) == displayID
            }
            return false
        }) else { return }

        let window: DisplayDimmingOverlayWindow
        if let existing = overlayWindows[displayID] {
            window = existing
            if window.frame != screen.frame {
                window.setFrame(screen.frame, display: true)
            }
        } else {
            window = DisplayDimmingOverlayWindow(screen: screen)
            overlayWindows[displayID] = window
        }

        window.setDimmingLevel(brightness)
    }

    public func removeOverlay(for displayID: CGDirectDisplayID) {
        if let win = overlayWindows.removeValue(forKey: displayID) {
            win.orderOut(nil)
            win.close()
        }
    }

    public func removeAllOverlays() {
        for (_, win) in overlayWindows {
            win.orderOut(nil)
            win.close()
        }
        overlayWindows.removeAll()
    }
}

final class DisplayDimmingOverlayWindow: NSWindow {
    private let shadeLayer = CALayer()

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        // Position below notch windows but above standard application windows
        self.level = NSWindow.Level(Int(CGWindowLevelForKey(.screenSaverWindow)) - 2)
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let hostView = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        hostView.wantsLayer = true

        shadeLayer.frame = hostView.bounds
        shadeLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        shadeLayer.backgroundColor = NSColor.black.cgColor
        shadeLayer.opacity = 0.0

        hostView.layer?.addSublayer(shadeLayer)
        self.contentView = hostView
    }

    func setDimmingLevel(_ brightness: Float) {
        // brightness 1.0 -> 0 opacity (invisible)
        // brightness 0.0 -> max 0.88 opacity (deep dimming without full black-out)
        let clamped = max(0.0, min(1.0, brightness))
        let targetOpacity = Float((1.0 - Double(clamped)) * 0.88)

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        shadeLayer.opacity = targetOpacity
        CATransaction.commit()

        if targetOpacity <= 0.005 {
            if self.isVisible {
                self.orderOut(nil)
            }
        } else {
            if !self.isVisible {
                self.orderFrontRegardless()
            }
        }
    }
}
