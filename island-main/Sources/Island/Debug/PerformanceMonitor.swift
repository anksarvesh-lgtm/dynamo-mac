import AppKit
import Darwin
import Observation
import QuartzCore

/// CPU / memory / main-thread FPS sampling. Runs ONLY while the debug panel or performance overlay is
/// visible, so it costs nothing in normal use.
@MainActor
@Observable
final class PerformanceMonitor {
    private(set) var cpuPercent: Double = 0
    private(set) var memoryMB: Double = 0
    private(set) var fps: Double = 0
    @ObservationIgnored private var sampler: Timer?
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var lastCPU: (time: Double, wall: Date)?
    @ObservationIgnored private var clients = 0

    func acquire(view: NSView?) {
        clients += 1
        guard clients == 1 else { return }
        sample()
        sampler = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        if let view {
            let link = view.displayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    func release() {
        clients = max(0, clients - 1)
        guard clients == 0 else { return }
        sampler?.invalidate()
        sampler = nil
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() { frames += 1 }

    private func sample() {
        fps = Double(frames)
        frames = 0
        memoryMB = Self.footprintMB()
        let cpu = Self.cpuTimeSeconds()
        let now = Date()
        if let last = lastCPU {
            let wall = now.timeIntervalSince(last.wall)
            if wall > 0 { cpuPercent = max(0, (cpu - last.time) / wall * 100) }
        }
        lastCPU = (cpu, now)
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    static func cpuTimeSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func s(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return s(usage.ru_utime) + s(usage.ru_stime)
    }
}
