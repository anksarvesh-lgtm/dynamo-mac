//
//  PlexoNetworkManager.swift
//  LiquidDynamo
//
//  Discovers all hardware and virtual network interfaces on macOS:
//  - Queries `networksetup -listallhardwareports` for human-readable port labels
//  - Enumerates BSD devices and IP addresses via Darwin `getifaddrs`
//  - Continuously monitors interface state via `NWPathMonitor`
//  - Measures real-time per-interface bandwidth throughput
//  - Manages per-interface enable toggles, custom nicknames, and color themes
//  Faithfully ported from Plexo (https://github.com/anmolkapil/plexo).
//

import Combine
import Foundation
import Network
import SystemConfiguration

@MainActor
public final class PlexoNetworkManager: ObservableObject {
    public static let shared = PlexoNetworkManager()

    @Published public private(set) var interfaces: [PlexoInterface] = []
    @Published public private(set) var totalDownloadSpeed: Double = 0
    @Published public private(set) var totalUploadSpeed: Double = 0

    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.liquiddynamo.plexo.network", qos: .utility)
    private var throughputTimer: Timer?
    private var previousInterfaceBytes: [String: (rx: UInt64, tx: UInt64, timestamp: Date)] = [:]
    private let defaultsKey = "plexoInterfaceCustomizations"

    private struct CustomizationRecord: Codable {
        var nickname: String?
        var colorHex: String?
        var isEnabled: Bool
        var speedLimitBytesPerSec: Double?
        var dataAllowanceBytes: Int64?
    }

    private init() {
        refreshInterfaces()
        setupPathMonitor()
        startThroughputTimer()
    }

    deinit {
        pathMonitor.cancel()
        throughputTimer?.invalidate()
    }

    // MARK: - Interface Discovery

    public func refreshInterfaces() {
        // 1. Hardware ports from SystemConfiguration (SCNetworkInterfaceCopyAll)
        let scAdapters = Self.querySystemConfigurationInterfaces()
        // 2. Hardware port name map from networksetup -listallhardwareports (supplementary)
        let hardwarePorts = Self.queryHardwarePortNames()
        // 3. Addresses and link state from getifaddrs
        let ifaddrsMap = Self.queryIfaddrsInfo()

        var discoveredMap: [String: PlexoInterface] = [:]
        let savedCustomizations = loadCustomizations()

        // First pass: add all physical and virtual adapters known to macOS SystemConfiguration
        for sc in scAdapters {
            let bsd = sc.bsdName
            let ifInfo = ifaddrsMap[bsd]
            let custom = savedCustomizations[bsd]
            let mac = sc.macAddress ?? ifInfo?.macAddress

            let iface = PlexoInterface(
                id: bsd,
                bsdName: bsd,
                displayName: sc.displayName,
                userNickname: custom?.nickname,
                kind: sc.kind,
                ipAddress: ifInfo?.ipv4,
                ipv6Address: ifInfo?.ipv6,
                macAddress: mac,
                netmask: ifInfo?.netmask,
                isEnabled: custom?.isEnabled ?? true,
                colorHex: custom?.colorHex ?? sc.kind.defaultColorHex,
                downloadSpeed: 0,
                uploadSpeed: 0,
                totalBytesDownloaded: 0,
                speedLimitBytesPerSec: custom?.speedLimitBytesPerSec,
                dataAllowanceBytes: custom?.dataAllowanceBytes
            )
            discoveredMap[bsd] = iface
        }

        // Second pass: any ports from networksetup not in SC
        for (bsd, portName) in hardwarePorts {
            guard discoveredMap[bsd] == nil else { continue }
            guard !bsd.hasPrefix("lo"), !bsd.hasPrefix("utun"), !bsd.hasPrefix("llw"), !bsd.hasPrefix("awdl"), !bsd.hasPrefix("ipsec") else { continue }
            let ifInfo = ifaddrsMap[bsd]
            let custom = savedCustomizations[bsd]
            let kind = Self.classifyInterface(hardwarePortName: portName, bsdName: bsd)

            let iface = PlexoInterface(
                id: bsd,
                bsdName: bsd,
                displayName: portName,
                userNickname: custom?.nickname,
                kind: kind,
                ipAddress: ifInfo?.ipv4,
                ipv6Address: ifInfo?.ipv6,
                macAddress: ifInfo?.macAddress,
                netmask: ifInfo?.netmask,
                isEnabled: custom?.isEnabled ?? true,
                colorHex: custom?.colorHex ?? kind.defaultColorHex,
                downloadSpeed: 0,
                uploadSpeed: 0,
                totalBytesDownloaded: 0,
                speedLimitBytesPerSec: custom?.speedLimitBytesPerSec,
                dataAllowanceBytes: custom?.dataAllowanceBytes
            )
            discoveredMap[bsd] = iface
        }

        // Third pass: any active network devices from getifaddrs (e.g. USB tethering, mobile hotspots)
        for (bsd, ifInfo) in ifaddrsMap {
            guard discoveredMap[bsd] == nil else { continue }
            guard !bsd.hasPrefix("lo"), !bsd.hasPrefix("utun"), !bsd.hasPrefix("llw"), !bsd.hasPrefix("awdl"), !bsd.hasPrefix("ipsec") else { continue }
            let custom = savedCustomizations[bsd]
            let fallbackName = hardwarePorts[bsd] ?? bsd
            let kind = Self.classifyInterface(hardwarePortName: fallbackName, bsdName: bsd)

            let iface = PlexoInterface(
                id: bsd,
                bsdName: bsd,
                displayName: fallbackName,
                userNickname: custom?.nickname,
                kind: kind,
                ipAddress: ifInfo.ipv4,
                ipv6Address: ifInfo.ipv6,
                macAddress: ifInfo.macAddress,
                netmask: ifInfo.netmask,
                isEnabled: custom?.isEnabled ?? true,
                colorHex: custom?.colorHex ?? kind.defaultColorHex,
                downloadSpeed: 0,
                uploadSpeed: 0,
                totalBytesDownloaded: 0,
                speedLimitBytesPerSec: custom?.speedLimitBytesPerSec,
                dataAllowanceBytes: custom?.dataAllowanceBytes
            )
            discoveredMap[bsd] = iface
        }

        var discovered = Array(discoveredMap.values)

        // Sort:
        // 1. Online adapters before offline adapters
        // 2. Wi-Fi first, then Ethernet, then USB, then Bridge, then other
        // 3. Alphabetical by BSD device name
        discovered.sort { lhs, rhs in
            if lhs.isOnline != rhs.isOnline {
                return lhs.isOnline && !rhs.isOnline
            }
            let order: [PlexoInterfaceKind: Int] = [.wifi: 0, .ethernet: 1, .usb: 2, .bridge: 3, .other: 4]
            let lhsOrder = order[lhs.kind] ?? 99
            let rhsOrder = order[rhs.kind] ?? 99
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            return lhs.bsdName < rhs.bsdName
        }

        self.interfaces = discovered
    }

    // MARK: - User Customizations

    public func setInterfaceEnabled(_ id: String, isEnabled: Bool) {
        if let idx = interfaces.firstIndex(where: { $0.id == id }) {
            interfaces[idx].isEnabled = isEnabled
            saveCustomizations()
        }
    }

    public func setInterfaceNickname(_ id: String, nickname: String?) {
        if let idx = interfaces.firstIndex(where: { $0.id == id }) {
            interfaces[idx].userNickname = nickname
            saveCustomizations()
        }
    }

    public func setInterfaceColor(_ id: String, colorHex: String) {
        if let idx = interfaces.firstIndex(where: { $0.id == id }) {
            interfaces[idx].colorHex = colorHex
            saveCustomizations()
        }
    }

    public func setInterfaceSpeedLimit(_ id: String, limit: Double?) {
        if let idx = interfaces.firstIndex(where: { $0.id == id }) {
            interfaces[idx].speedLimitBytesPerSec = limit
            saveCustomizations()
        }
    }

    public func setInterfaceDataAllowance(_ id: String, allowance: Int64?) {
        if let idx = interfaces.firstIndex(where: { $0.id == id }) {
            interfaces[idx].dataAllowanceBytes = allowance
            saveCustomizations()
        }
    }

    public var enabledInterfaces: [PlexoInterface] {
        interfaces.filter { $0.isEnabled }
    }

    public var activeConnectedInterfaces: [PlexoInterface] {
        let active = interfaces.filter { $0.isEnabled && $0.isOnline }
        return active.isEmpty ? interfaces.filter { $0.isEnabled } : active
    }

    // MARK: - Live Throughput Sampling

    private func startThroughputTimer() {
        throughputTimer?.invalidate()
        throughputTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sampleThroughput()
            }
        }
    }

    private func sampleThroughput() {
        let currentBytes = Self.queryInterfaceByteCounts()
        let now = Date()
        var totalDown: Double = 0
        var totalUp: Double = 0

        for i in 0..<interfaces.count {
            let bsd = interfaces[i].bsdName
            guard let current = currentBytes[bsd] else {
                interfaces[i].downloadSpeed = 0
                interfaces[i].uploadSpeed = 0
                continue
            }

            if let prev = previousInterfaceBytes[bsd] {
                let dt = now.timeIntervalSince(prev.timestamp)
                if dt > 0.1 {
                    let rxDelta = current.rx >= prev.rx ? (current.rx - prev.rx) : 0
                    let txDelta = current.tx >= prev.tx ? (current.tx - prev.tx) : 0
                    let downSpeed = Double(rxDelta) / dt
                    let upSpeed = Double(txDelta) / dt

                    interfaces[i].downloadSpeed = downSpeed
                    interfaces[i].uploadSpeed = upSpeed

                    if interfaces[i].isEnabled {
                        totalDown += downSpeed
                        totalUp += upSpeed
                    }
                }
            }
            previousInterfaceBytes[bsd] = (rx: current.rx, tx: current.tx, timestamp: now)
        }

        self.totalDownloadSpeed = totalDown
        self.totalUploadSpeed = totalUp
    }

    // MARK: - Path Monitor

    private func setupPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshInterfaces()
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    // MARK: - System Query Helpers

    private struct DiscoveredAdapter {
        var bsdName: String
        var displayName: String
        var kind: PlexoInterfaceKind
        var macAddress: String?
    }

    private struct InterfaceAddressInfo {
        var ipv4: String?
        var ipv6: String?
        var netmask: String?
        var macAddress: String?
        var isUp: Bool
        var isRunning: Bool
    }

    private static func querySystemConfigurationInterfaces() -> [DiscoveredAdapter] {
        var results: [DiscoveredAdapter] = []
        guard let allInterfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else {
            return results
        }

        for iface in allInterfaces {
            guard let bsd = SCNetworkInterfaceGetBSDName(iface) as String?, !bsd.isEmpty else { continue }
            // Ignore loopback and internal virtual tunnels
            guard !bsd.hasPrefix("lo"), !bsd.hasPrefix("utun"), !bsd.hasPrefix("llw"), !bsd.hasPrefix("awdl"), !bsd.hasPrefix("ipsec") else { continue }

            let rawName = (SCNetworkInterfaceGetLocalizedDisplayName(iface) as String?) ?? bsd
            let type = SCNetworkInterfaceGetInterfaceType(iface) as String?
            let mac = SCNetworkInterfaceGetHardwareAddressString(iface) as String?

            let kind = classifyInterface(hardwarePortName: rawName, bsdName: bsd, scType: type)
            results.append(DiscoveredAdapter(bsdName: bsd, displayName: rawName, kind: kind, macAddress: mac))
        }
        return results
    }

    private static func queryIfaddrsInfo() -> [String: InterfaceAddressInfo] {
        var result: [String: InterfaceAddressInfo] = [:]
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return result }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            guard let namePtr = current.pointee.ifa_name else { continue }
            let name = String(cString: namePtr)
            guard !name.hasPrefix("lo"), !name.hasPrefix("utun"), !name.hasPrefix("llw"), !name.hasPrefix("awdl"), !name.hasPrefix("ipsec") else { continue }
            guard let addrPtr = current.pointee.ifa_addr else { continue }

            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isRunning = (flags & IFF_RUNNING) != 0

            var entry = result[name] ?? InterfaceAddressInfo(ipv4: nil, ipv6: nil, netmask: nil, macAddress: nil, isUp: isUp, isRunning: isRunning)
            entry.isUp = entry.isUp || isUp
            entry.isRunning = entry.isRunning || isRunning

            let family = addrPtr.pointee.sa_family
            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))

            if family == AF_INET {
                var addrCopy = addrPtr.pointee
                if getnameinfo(&addrCopy, socklen_t(addrCopy.sa_len), &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ipStr = String(cString: hostBuffer)
                    if !ipStr.hasPrefix("127.") && !ipStr.hasPrefix("169.254.") {
                        entry.ipv4 = ipStr
                    }
                }
                if let maskPtr = current.pointee.ifa_netmask {
                    var maskCopy = maskPtr.pointee
                    var maskBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(&maskCopy, socklen_t(maskCopy.sa_len), &maskBuffer, socklen_t(maskBuffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                        entry.netmask = String(cString: maskBuffer)
                    }
                }
            } else if family == AF_INET6 {
                var addrCopy = addrPtr.pointee
                if getnameinfo(&addrCopy, socklen_t(addrCopy.sa_len), &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ipStr = String(cString: hostBuffer)
                    let cleanIP = ipStr.components(separatedBy: "%").first ?? ipStr
                    if !cleanIP.hasPrefix("::1") && !cleanIP.lowercased().hasPrefix("fe80:") {
                        entry.ipv6 = cleanIP
                    }
                }
            } else if family == AF_LINK {
                let dlPtr = addrPtr.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { $0 }
                if dlPtr.pointee.sdl_alen == 6 {
                    let sdlData = withUnsafePointer(to: dlPtr.pointee.sdl_data) { ptr -> UnsafePointer<UInt8> in
                        UnsafeRawPointer(ptr).assumingMemoryBound(to: UInt8.self)
                    }
                    let nlen = Int(dlPtr.pointee.sdl_nlen)
                    let macBytes = (0..<6).map { sdlData[nlen + $0] }
                    let macStr = macBytes.map { String(format: "%02x", $0) }.joined(separator: ":")
                    if macStr != "00:00:00:00:00:00" && entry.macAddress == nil {
                        entry.macAddress = macStr
                    }
                }
            }

            result[name] = entry
        }
        return result
    }

    private static func queryHardwarePortNames() -> [String: String] {
        var map: [String: String] = [:]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-listallhardwareports"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            if let output = String(data: data, encoding: .utf8) {
                let blocks = output.components(separatedBy: "\n\n")
                for block in blocks {
                    let lines = block.components(separatedBy: .newlines)
                    var currentPort: String?
                    var currentDevice: String?
                    for line in lines {
                        if line.hasPrefix("Hardware Port:") {
                            currentPort = line.replacingOccurrences(of: "Hardware Port:", with: "").trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("Device:") {
                            currentDevice = line.replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces)
                        }
                    }
                    if let port = currentPort, let device = currentDevice, !device.isEmpty {
                        map[device] = port
                    }
                }
            }
        } catch {
            // networksetup missing or sandboxed; fall back to default device names
        }
        return map
    }

    private static func queryInterfaceByteCounts() -> [String: (rx: UInt64, tx: UInt64)] {
        var result: [String: (rx: UInt64, tx: UInt64)] = [:]
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return result }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            guard let namePtr = current.pointee.ifa_name else { continue }
            let name = String(cString: namePtr)
            guard let addrPtr = current.pointee.ifa_addr else { continue }

            if addrPtr.pointee.sa_family == AF_LINK {
                if let dataPtr = current.pointee.ifa_data {
                    let ifData = dataPtr.assumingMemoryBound(to: if_data.self).pointee
                    result[name] = (rx: UInt64(ifData.ifi_ibytes), tx: UInt64(ifData.ifi_obytes))
                }
            }
        }
        return result
    }

    private static func classifyInterface(hardwarePortName: String, bsdName: String, scType: String? = nil) -> PlexoInterfaceKind {
        if let scType {
            if scType == (kSCNetworkInterfaceTypeIEEE80211 as String) {
                return .wifi
            } else if scType.lowercased().contains("bridge") {
                return .bridge
            }
        }

        let name = hardwarePortName.lowercased()
        if name.contains("wi-fi") || name.contains("wireless") || name.contains("wlan") || name.contains("airport") || name.contains("802.11") {
            return .wifi
        }
        if name.contains("iphone") || name.contains("ipad") || name.contains("tether") || name.contains("rndis") || name.contains("usb") || name.contains("apple mobile") {
            return .usb
        }
        if name.contains("bridge") || name.contains("thunderbolt bridge") {
            return .bridge
        }
        if name.contains("ethernet") || name.contains("lan") || name.contains("thunderbolt") {
            return .ethernet
        }
        if bsdName.hasPrefix("en") {
            return .ethernet
        }
        return .other
    }

    // MARK: - Persistence

    private func saveCustomizations() {
        var map: [String: CustomizationRecord] = [:]
        for iface in interfaces {
            map[iface.bsdName] = CustomizationRecord(
                nickname: iface.userNickname,
                colorHex: iface.colorHex,
                isEnabled: iface.isEnabled,
                speedLimitBytesPerSec: iface.speedLimitBytesPerSec,
                dataAllowanceBytes: iface.dataAllowanceBytes
            )
        }
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func loadCustomizations() -> [String: CustomizationRecord] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: CustomizationRecord].self, from: data) else {
            return [:]
        }
        return decoded
    }
}
