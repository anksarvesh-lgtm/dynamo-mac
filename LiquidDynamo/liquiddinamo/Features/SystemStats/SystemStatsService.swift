//
//  SystemStatsService.swift
//  boringNotch
//
//  Created for Boring Notch
//

import Combine
import Darwin
import Foundation
import SwiftUI

@MainActor
final class SystemStatsService: ObservableObject {
    static let shared = SystemStatsService()

    @Published private(set) var overallCPU: Double = 0.0          // 0.0 to 100.0%
    @Published private(set) var coreUsages: [Double] = []         // Per-core 0.0 to 100.0%
    @Published private(set) var memoryUsed: UInt64 = 0            // Bytes
    @Published private(set) var memoryTotal: UInt64 = 0           // Bytes
    @Published private(set) var cpuHistory: [Double] = []         // Last 60 samples
    @Published private(set) var isRunning: Bool = false

    var memoryPercentage: Double {
        guard memoryTotal > 0 else { return 0.0 }
        return (Double(memoryUsed) / Double(memoryTotal)) * 100.0
    }

    var formattedMemoryUsed: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryUsed), countStyle: .memory)
    }

    var formattedMemoryTotal: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryTotal), countStyle: .memory)
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

    private init() {
        memoryTotal = ProcessInfo.processInfo.physicalMemory
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Reset previous baseline so the first delta is clean
        previousCoreLoads = []

        // Initial snapshot
        sample()

        // Create timer firing once per second
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning else { return }
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
        previousCoreLoads = []
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
            self.memoryUsed = active + wired + compressed
            self.memoryTotal = ProcessInfo.processInfo.physicalMemory
        }
    }
}
