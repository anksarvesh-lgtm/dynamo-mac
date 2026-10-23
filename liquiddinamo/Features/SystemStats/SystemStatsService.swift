//
//  SystemStatsService.swift
//  boringNotch
//
//  Created for Boring Notch
//

import Combine
import Darwin
import Defaults
import Foundation
import IOKit.ps
import QuartzCore
import SwiftUI

@MainActor
final class SystemStatsService: ObservableObject {
    static let shared = SystemStatsService()

    @Published private(set) var overallCPU: Double = 0.0          // 0.0 to 100.0%
    @Published private(set) var coreUsages: [Double] = []         // Per-core 0.0 to 100.0%
    @Published private(set) var memoryUsed: UInt64 = 0            // Bytes
    @Published private(set) var memoryAvailable: UInt64 = 0       // Bytes
    @Published private(set) var memoryTotal: UInt64 = 0           // Bytes
    @Published private(set) var memoryPressure: Double = 0.0      // 0.0 to 1.0
    @Published private(set) var cpuHistory: [Double] = []         // Last 60 samples
    @Published private(set) var isRunning: Bool = false

    // Real CPU Temperature (IOHID on Apple Silicon, fallback to nil if unavailable)
    @Published private(set) var cpuTemperature: Double? = nil
    @Published private(set) var isTemperatureAvailable: Bool = false

    var formattedCPUTemperature: String {
        if let temp = cpuTemperature {
            return String(format: "%.0f°C", temp)
        } else {
            return "—"
        }
    }

    // Thermal State (ProcessInfo.thermalState - 100% public, non-invented)
    @Published private(set) var thermalState: ProcessInfo.ThermalState = .nominal

    // Date & Time in user's locale (updates each second only while open)
    @Published private(set) var formattedDate: String = ""
    @Published private(set) var formattedTime: String = ""

    // Battery / Power
    @Published private(set) var batteryPercentage: Int = 100
    @Published private(set) var isBatteryCharging: Bool = false
    @Published private(set) var isBatteryPluggedIn: Bool = true
    @Published private(set) var batteryTimeRemaining: String = ""

    var memoryPercentage: Double {
        guard memoryTotal > 0 else { return 0.0 }
        return (Double(memoryUsed) / Double(memoryTotal)) * 100.0
    }

    var formattedMemoryUsed: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryUsed), countStyle: .memory)
    }

    var formattedMemoryAvailable: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryAvailable), countStyle: .memory)
    }

    var formattedMemoryTotal: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryTotal), countStyle: .memory)
    }

    var thermalStateTitle: String {
        switch thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Nominal"
        }
    }

    var thermalStateColor: Color {
        switch thermalState {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .green
        }
    }

    var thermalStateIcon: String {
        switch thermalState {
        case .nominal: return "thermometer.low"
        case .fair: return "thermometer.medium"
        case .serious: return "thermometer.high"
        case .critical: return "exclamationmark.triangle.fill"
        @unknown default: return "thermometer.low"
        }
    }

    private struct CoreLoad {
        var user: UInt32
        var system: UInt32
        var idle: UInt32
        var nice: UInt32
    }

    private var previousCoreLoads: [CoreLoad] = []
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.agrigence.liquiddynamo.systemstats", qos: .utility)
    private let maxHistorySamples = 60
    private var thermalObserver: Any?

    private init() {
        memoryTotal = ProcessInfo.processInfo.physicalMemory
        updateDateTime()
        updateThermalState()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Reset previous baseline so the first delta is clean
        previousCoreLoads = []

        // Register thermal state notifications while active
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateThermalState()
        }

        // Initial snapshot
        updateDateTime()
        updateThermalState()
        sample()

        // Create timer firing at configured interval (slowed down in Low Power Mode)
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let baseInterval = max(1.0, Defaults[.sideReadoutInterval])
        let effectiveInterval = isLowPower ? max(3.0, baseInterval * 2.0) : baseInterval

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + effectiveInterval, repeating: effectiveInterval, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning else { return }
                self.updateDateTime()
                self.sample()
            }
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        if let timer = timer {
            timer.cancel()
            self.timer = nil
        }
        if let observer = thermalObserver {
            NotificationCenter.default.removeObserver(observer)
            thermalObserver = nil
        }
        previousCoreLoads = []
    }

    private func updateDateTime() {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.current
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        self.formattedDate = dateFormatter.string(from: now)

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale.current
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .medium
        self.formattedTime = timeFormatter.string(from: now)
    }

    private func updateThermalState() {
        self.thermalState = ProcessInfo.processInfo.thermalState
    }

    private func sample() {
        let hostPort = mach_host_self()
        defer {
            mach_port_deallocate(mach_task_self_, hostPort)
        }

        // Sample CPU via host_processor_info
        var numCPUsU: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            hostPort,
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUsU,
            &cpuInfo,
            &numCpuInfo
        )

        if result == KERN_SUCCESS, let cpuInfo = cpuInfo {
            let numCPUs = Int(numCPUsU)
            var currentLoads: [CoreLoad] = []
            currentLoads.reserveCapacity(numCPUs)

            for i in 0..<numCPUs {
                let base = i * Int(CPU_STATE_MAX)
                let user = UInt32(cpuInfo[base + Int(CPU_STATE_USER)])
                let system = UInt32(cpuInfo[base + Int(CPU_STATE_SYSTEM)])
                let idle = UInt32(cpuInfo[base + Int(CPU_STATE_IDLE)])
                let nice = UInt32(cpuInfo[base + Int(CPU_STATE_NICE)])
                currentLoads.append(CoreLoad(user: user, system: system, idle: idle, nice: nice))
            }

            if !previousCoreLoads.isEmpty && previousCoreLoads.count == currentLoads.count {
                var newCoreUsages: [Double] = []
                newCoreUsages.reserveCapacity(numCPUs)
                var totalUsage: Double = 0.0

                for i in 0..<numCPUs {
                    let prev = previousCoreLoads[i]
                    let curr = currentLoads[i]

                    let dUser = Double(curr.user >= prev.user ? curr.user - prev.user : 0)
                    let dSystem = Double(curr.system >= prev.system ? curr.system - prev.system : 0)
                    let dIdle = Double(curr.idle >= prev.idle ? curr.idle - prev.idle : 0)
                    let dNice = Double(curr.nice >= prev.nice ? curr.nice - prev.nice : 0)

                    let dTotal = dUser + dSystem + dIdle + dNice
                    let usage = dTotal > 0 ? ((dUser + dSystem + dNice) / dTotal) * 100.0 : 0.0
                    let clamped = min(max(usage, 0.0), 100.0)
                    newCoreUsages.append(clamped)
                    totalUsage += clamped
                }

                let newOverall = numCPUs > 0 ? totalUsage / Double(numCPUs) : 0.0
                self.overallCPU = newOverall
                self.coreUsages = newCoreUsages

                // Append to history buffer
                var history = cpuHistory
                history.append(newOverall)
                if history.count > maxHistorySamples {
                    history.removeFirst(history.count - maxHistorySamples)
                }
                self.cpuHistory = history
            }

            previousCoreLoads = currentLoads

            let cpuInfoByteCount = vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), cpuInfoByteCount)
        }

        // Sample Memory via host_statistics64
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(hostPort, HOST_VM_INFO64, intPtr, &count)
            }
        }

        if vmResult == KERN_SUCCESS {
            var pageSize: vm_size_t = 0
            host_page_size(hostPort, &pageSize)
            let active = UInt64(vmStats.active_count) * UInt64(pageSize)
            let wired = UInt64(vmStats.wire_count) * UInt64(pageSize)
            let compressed = UInt64(vmStats.compressor_page_count) * UInt64(pageSize)
            let free = UInt64(vmStats.free_count) * UInt64(pageSize)
            let inactive = UInt64(vmStats.inactive_count) * UInt64(pageSize)

            self.memoryUsed = active + wired + compressed
            self.memoryAvailable = free + inactive
            self.memoryTotal = ProcessInfo.processInfo.physicalMemory

            if memoryTotal > 0 {
                self.memoryPressure = min(max(Double(active + wired + compressed) / Double(memoryTotal), 0.0), 1.0)
            }
        }

        // Sample Battery / Power Source via IOKit.ps
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
           let firstSource = sources.first,
           let description = IOPSGetPowerSourceDescription(snapshot, firstSource)?.takeUnretainedValue() as? [String: Any] {

            if let currentCap = description[kIOPSCurrentCapacityKey] as? Int,
               let maxCap = description[kIOPSMaxCapacityKey] as? Int, maxCap > 0 {
                self.batteryPercentage = min(max(Int((Double(currentCap) / Double(maxCap)) * 100.0), 0), 100)
            } else if let curFloat = description[kIOPSCurrentCapacityKey] as? Float {
                self.batteryPercentage = Int(curFloat)
            }

            let isCharging = (description["Is Charging"] as? Bool) ?? false
            self.isBatteryCharging = isCharging

            let powerState = (description[kIOPSPowerSourceStateKey] as? String) ?? ""
            self.isBatteryPluggedIn = (powerState == kIOPSACPowerValue)

            if isCharging {
                if let timeToFull = description[kIOPSTimeToFullChargeKey] as? Int, timeToFull > 0 {
                    let hrs = timeToFull / 60
                    let mins = timeToFull % 60
                    self.batteryTimeRemaining = hrs > 0 ? "\(hrs)h \(mins)m to full" : "\(mins)m to full"
                } else {
                    self.batteryTimeRemaining = "Charging"
                }
            } else if isBatteryPluggedIn {
                self.batteryTimeRemaining = "Plugged in"
            } else if let timeToEmpty = description[kIOPSTimeToEmptyKey] as? Int, timeToEmpty > 0 {
                let hrs = timeToEmpty / 60
                let mins = timeToEmpty % 60
                self.batteryTimeRemaining = hrs > 0 ? "\(hrs)h \(mins)m remaining" : "\(mins)m remaining"
            } else {
                self.batteryTimeRemaining = "Calculating…"
            }
        }

        // Sample real CPU temperature via IOHID (Apple Silicon)
        if let temp = sampleCPUTemperature() {
            self.cpuTemperature = temp
            self.isTemperatureAvailable = true
        } else {
            self.cpuTemperature = nil
            self.isTemperatureAvailable = false
        }
    }

    // Cached IOHID handles & services to prevent CPU spikes
    private struct IOHIDCache {
        typealias ClientCreate = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
        typealias SetMatching = @convention(c) (CFTypeRef, CFDictionary) -> Void
        typealias CopyServices = @convention(c) (CFTypeRef) -> CFArray?
        typealias CopyProperty = @convention(c) (CFTypeRef, CFString) -> CFTypeRef?
        typealias CopyEvent = @convention(c) (CFTypeRef, UInt32, Int64, UInt32) -> CFTypeRef?
        typealias GetFloatValue = @convention(c) (CFTypeRef, UInt32) -> Double

        let client: CFTypeRef
        let copyEvent: CopyEvent
        let getFloatValue: GetFloatValue
        let cpuServices: [CFTypeRef]
        let fallbackServices: [CFTypeRef]

        static let shared: IOHIDCache? = {
            guard let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else { return nil }
            guard let createSym = dlsym(iokit, "IOHIDEventSystemClientCreate"),
                  let matchSym = dlsym(iokit, "IOHIDEventSystemClientSetMatching"),
                  let copyServicesSym = dlsym(iokit, "IOHIDEventSystemClientCopyServices"),
                  let copyPropertySym = dlsym(iokit, "IOHIDServiceClientCopyProperty"),
                  let copyEventSym = dlsym(iokit, "IOHIDServiceClientCopyEvent"),
                  let getFloatSym = dlsym(iokit, "IOHIDEventGetFloatValue") else {
                return nil
            }
            let clientCreate = unsafeBitCast(createSym, to: ClientCreate.self)
            let setMatching = unsafeBitCast(matchSym, to: SetMatching.self)
            let copyServices = unsafeBitCast(copyServicesSym, to: CopyServices.self)
            let copyProperty = unsafeBitCast(copyPropertySym, to: CopyProperty.self)
            let copyEvent = unsafeBitCast(copyEventSym, to: CopyEvent.self)
            let getFloatValue = unsafeBitCast(getFloatSym, to: GetFloatValue.self)

            guard let client = clientCreate(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
            let match: [String: Any] = [
                "PrimaryUsagePage": 0xff00,
                "PrimaryUsage": 0x05
            ]
            setMatching(client, match as CFDictionary)
            guard let allServices = copyServices(client) as? [CFTypeRef], !allServices.isEmpty else { return nil }

            var cpu: [CFTypeRef] = []
            var fallback: [CFTypeRef] = []
            for s in allServices {
                let product = (copyProperty(s, "Product" as CFString) as? String)?.lowercased() ?? ""
                if product.contains("tdie") || product.contains("cpu") {
                    cpu.append(s)
                } else if !product.contains("battery") && !product.contains("gas gauge") {
                    fallback.append(s)
                }
            }
            return IOHIDCache(
                client: client,
                copyEvent: copyEvent,
                getFloatValue: getFloatValue,
                cpuServices: cpu,
                fallbackServices: fallback
            )
        }()
    }

    private var lastTempSampleTime: TimeInterval = 0

    private func sampleCPUTemperature() -> Double? {
        let now = CACurrentMediaTime()
        // Throttle temperature sampling to once every 3.5 seconds to eliminate CPU overhead
        if now - lastTempSampleTime < 3.5, let existing = self.cpuTemperature {
            return existing
        }
        lastTempSampleTime = now

        guard let cache = IOHIDCache.shared else { return nil }

        let targets = !cache.cpuServices.isEmpty ? cache.cpuServices : cache.fallbackServices
        guard !targets.isEmpty else { return nil }

        var temps: [Double] = []
        for s in targets {
            if let event = cache.copyEvent(s, 15, 0, 0) {
                let temp = cache.getFloatValue(event, 15 << 16)
                if temp >= 15.0 && temp <= 115.0 {
                    temps.append(temp)
                }
            }
        }

        if !temps.isEmpty {
            return temps.reduce(0, +) / Double(temps.count)
        }
        return nil
    }
}
