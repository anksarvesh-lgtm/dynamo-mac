//
//  PowerloadNetworkManager.swift
//  LiquidDynamo
//
//  Discovers all hardware and virtual network interfaces on macOS:
//  - Queries SystemConfiguration (SCNetworkSetCopyServices & SCNetworkInterfaceCopyAll)
//  - Language-agnostic hardware port lookup from `networksetup -listallhardwareports`
//  - SCDynamicStore inspection for instantaneous hardware link state & IP assignment
//  - Enumerates BSD devices and IP addresses via Darwin `getifaddrs`
//  - Continuously monitors interface state via `NWPathMonitor` and 1-second dynamic checks
//  - Measures real-time per-interface bandwidth throughput
//  - Manages per-interface enable toggles, custom nicknames, and color themes
//  Rebranded and enhanced from Plexo (https://github.com/anmolkapil/plexo).
//

import Combine
import Defaults
import Foundation
import Network
import SystemConfiguration

@MainActor
public final class PowerloadNetworkManager: ObservableObject {
    public static let shared = PowerloadNetworkManager()

    @Published public private(set) var interfaces: [PowerloadInterface] = []
    @Published public private(set) var totalDownloadSpeed: Double = 0
    @Published public private(set) var totalUploadSpeed: Double = 0

    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.liquiddynamo.powerload.network", qos: .utility)
    private var throughputTimer: Timer?
    private var previousInterfaceBytes: [String: (rx: UInt64, tx: UInt64, timestamp: Date)] = [:]
    private let defaultsKey = "powerloadInterfaceCustomizations"
    private var dynamicStore: SCDynamicStore?

    private struct CustomizationRecord: Codable {
        var nickname: String?
        var colorHex: String?
        var isEnabled: Bool
        var speedLimitBytesPerSec: Double?
        var dataAllowanceBytes: Int64?
    }

    private init() {
        self.dynamicStore = SCDynamicStoreCreate(nil, "com.liquiddynamo.powerload" as CFString, nil, nil)
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
        // 1. Hardware ports from SystemConfiguration (SCNetworkInterfaceCopyAll & SCNetworkSetCopyServices)
        let scAdapters = Self.querySystemConfigurationInterfaces()
        // 2. Hardware port name map from networksetup -listallhardwareports (language-agnostic)
        let hardwarePorts = Self.queryHardwarePortNames()
        // 3. Addresses and link state from getifaddrs
        let ifaddrsMap = Self.queryIfaddrsInfo()
        // 4. Live SCDynamicStore link state map
        let linkStateMap = Self.queryDynamicStoreLinkStates(store: dynamicStore)
        // 5. Authoritative gateway IP map from SCDynamicStore
        let gatewayMap = Self.queryGatewayIPs(store: dynamicStore)

        var discoveredMap: [String: PowerloadInterface] = [:]
        let savedCustomizations = loadCustomizations()

        // First pass: add all physical adapters known to macOS SystemConfiguration
        for sc in scAdapters {
            let bsd = sc.bsdName
            guard !Self.isVirtualInterface(bsdName: bsd) else { continue }
            let ifInfo = ifaddrsMap[bsd]
            let custom = savedCustomizations[bsd]
            let mac = sc.macAddress ?? ifInfo?.macAddress
            let isLinkActive = linkStateMap[bsd] ?? (ifInfo?.isUp == true && ifInfo?.isRunning == true)
            let gatewayIP = gatewayMap[bsd]
            let isMetered = Self.isInterfaceMetered(kind: sc.kind, portName: sc.displayName, bsdName: bsd)
            let health = Self.initialHealth(hasIPv4: ifInfo?.ipv4 != nil, isLinkActive: isLinkActive, gatewayIP: gatewayIP)

            let iface = PowerloadInterface(
                id: bsd,
                bsdName: bsd,
                displayName: sc.displayName,
                userNickname: custom?.nickname,
                kind: sc.kind,
                ipAddress: ifInfo?.ipv4,
                ipv6Address: ifInfo?.ipv6,
                macAddress: mac,
                netmask: ifInfo?.netmask,
                gatewayIP: gatewayIP,
                isLinkActive: isLinkActive,
                isEnabled: custom?.isEnabled ?? true,
                isMetered: isMetered,
                health: health,
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
            guard !Self.isVirtualInterface(bsdName: bsd) else { continue }
            let ifInfo = ifaddrsMap[bsd]
            let custom = savedCustomizations[bsd]
            let kind = Self.classifyInterface(hardwarePortName: portName, bsdName: bsd)
            let isLinkActive = linkStateMap[bsd] ?? (ifInfo?.isUp == true && ifInfo?.isRunning == true)
            let gatewayIP = gatewayMap[bsd]
            let isMetered = Self.isInterfaceMetered(kind: kind, portName: portName, bsdName: bsd)
            let health = Self.initialHealth(hasIPv4: ifInfo?.ipv4 != nil, isLinkActive: isLinkActive, gatewayIP: gatewayIP)

            let iface = PowerloadInterface(
                id: bsd,
                bsdName: bsd,
                displayName: portName,
                userNickname: custom?.nickname,
                kind: kind,
                ipAddress: ifInfo?.ipv4,
                ipv6Address: ifInfo?.ipv6,
                macAddress: ifInfo?.macAddress,
                netmask: ifInfo?.netmask,
                gatewayIP: gatewayIP,
                isLinkActive: isLinkActive,
                isEnabled: custom?.isEnabled ?? true,
                isMetered: isMetered,
                health: health,
                colorHex: custom?.colorHex ?? kind.defaultColorHex,
                downloadSpeed: 0,
                uploadSpeed: 0,
                totalBytesDownloaded: 0,
                speedLimitBytesPerSec: custom?.speedLimitBytesPerSec,
                dataAllowanceBytes: custom?.dataAllowanceBytes
            )
            discoveredMap[bsd] = iface
        }

        // Third pass: any active network devices from getifaddrs (e.g. USB tethering, mobile hotspots, Thunderbolt)
        for (bsd, ifInfo) in ifaddrsMap {
            guard discoveredMap[bsd] == nil else { continue }
            guard !Self.isVirtualInterface(bsdName: bsd) else { continue }
            let custom = savedCustomizations[bsd]
            let fallbackName = hardwarePorts[bsd] ?? bsd
            let kind = Self.classifyInterface(hardwarePortName: fallbackName, bsdName: bsd)
            let isLinkActive = linkStateMap[bsd] ?? (ifInfo.isUp && ifInfo.isRunning)
            let gatewayIP = gatewayMap[bsd]
            let isMetered = Self.isInterfaceMetered(kind: kind, portName: fallbackName, bsdName: bsd)
            let health = Self.initialHealth(hasIPv4: ifInfo.ipv4 != nil, isLinkActive: isLinkActive, gatewayIP: gatewayIP)

            let iface = PowerloadInterface(
                id: bsd,
                bsdName: bsd,
                displayName: fallbackName,
                userNickname: custom?.nickname,
                kind: kind,
                ipAddress: ifInfo.ipv4,
                ipv6Address: ifInfo.ipv6,
                macAddress: ifInfo.macAddress,
                netmask: ifInfo.netmask,
                gatewayIP: gatewayIP,
                isLinkActive: isLinkActive,
                isEnabled: custom?.isEnabled ?? true,
                isMetered: isMetered,
                health: health,
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
        // 1. Interfaces with IP / Online first
        // 2. Interfaces with physical Link Active second
        // 3. Kind order: Wi-Fi, Ethernet, USB / Mobile, Bridge, Other
        // 4. Alphabetical BSD name
        discovered.sort { lhs, rhs in
            if lhs.hasIP != rhs.hasIP {
                return lhs.hasIP && !rhs.hasIP
            }
            if lhs.isLinkActive != rhs.isLinkActive {
                return lhs.isLinkActive && !rhs.isLinkActive
            }
            let order: [PowerloadInterfaceKind: Int] = [.wifi: 0, .ethernet: 1, .usb: 2, .bridge: 3, .other: 4]
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

    public var enabledInterfaces: [PowerloadInterface] {
        interfaces.filter { $0.isEnabled }
    }

    public var activeConnectedInterfaces: [PowerloadInterface] {
        let allowMetered = Defaults[.powerloadUseMeteredConnections]
        let usable = interfaces.filter { iface in
            guard iface.isEnabled && iface.isOnline else { return false }
            if iface.isMetered && !allowMetered {
                return false
            }
            return true
        }
        return usable
    }

    public func evaluateInterfaceHealth(_ bsdName: String) async -> PowerloadHealthState {
        guard let idx = interfaces.firstIndex(where: { $0.bsdName == bsdName }) else {
            return .unusable(reason: "Interface not found")
        }
        let iface = interfaces[idx]
        guard iface.isLinkActive else {
            let state = PowerloadHealthState.unusable(reason: "Physical link down")
            interfaces[idx].health = state
            return state
        }
        guard iface.ipAddress != nil else {
            let state = PowerloadHealthState.unusable(reason: "No IPv4 address assigned")
            interfaces[idx].health = state
            return state
        }
        guard iface.gatewayIP != nil else {
            let state = PowerloadHealthState.degraded(reason: "No default gateway")
            interfaces[idx].health = state
            return state
        }

        let probeURL = URL(string: "https://captive.apple.com/hotspot-detect.html")!
        let isReachable = await PowerloadHTTPClient.shared.probeInterface(bsdName: bsdName, url: probeURL, timeout: 3.0)
        let state: PowerloadHealthState = isReachable ? .usable : .degraded(reason: "Gateway unreachable")
        interfaces[idx].health = state
        return state
    }

    // MARK: - Live Throughput Sampling & Periodic Interface Verification

    private func startThroughputTimer() {
        throughputTimer?.invalidate()
        var tickCount = 0
        throughputTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.sampleThroughput()
                tickCount += 1
                // Check for new hot-plugged devices or link changes every 2 seconds
                if tickCount % 2 == 0 {
                    self.verifyHardwareInterfacesIfNeeded()
                }
            }
        }
    }

    private func verifyHardwareInterfacesIfNeeded() {
        let currentLink = Self.queryDynamicStoreLinkStates(store: dynamicStore)
        var needsRefresh = false
        for iface in interfaces {
            let active = currentLink[iface.bsdName] ?? false
            if active != iface.isLinkActive {
                needsRefresh = true
                break
            }
        }
        if needsRefresh {
            refreshInterfaces()
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
        var kind: PowerloadInterfaceKind
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

        // 1. Check current network set services for user-configured names
        if let prefs = SCPreferencesCreate(nil, "Powerload" as CFString, nil),
           let currentSet = SCNetworkSetCopyCurrent(prefs),
           let services = SCNetworkSetCopyServices(currentSet) as? [SCNetworkService] {
            for service in services {
                guard let iface = SCNetworkServiceGetInterface(service),
                      let bsd = SCNetworkInterfaceGetBSDName(iface) as String?,
                      !bsd.isEmpty else { continue }
                guard !bsd.hasPrefix("lo"), !bsd.hasPrefix("utun"), !bsd.hasPrefix("llw"), !bsd.hasPrefix("awdl"), !bsd.hasPrefix("ipsec"), !bsd.hasPrefix("anpi") else { continue }

                let serviceName = (SCNetworkServiceGetName(service) as String?) ?? bsd
                let type = SCNetworkInterfaceGetInterfaceType(iface) as String?
                let mac = SCNetworkInterfaceGetHardwareAddressString(iface) as String?
                let kind = classifyInterface(hardwarePortName: serviceName, bsdName: bsd, scType: type)
                results.append(DiscoveredAdapter(bsdName: bsd, displayName: serviceName, kind: kind, macAddress: mac))
            }
        }

        // 2. Supplement with SCNetworkInterfaceCopyAll for any raw interfaces not in default service set
        if let allInterfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for iface in allInterfaces {
                guard let bsd = SCNetworkInterfaceGetBSDName(iface) as String?, !bsd.isEmpty else { continue }
                guard results.contains(where: { $0.bsdName == bsd }) == false else { continue }
                guard !bsd.hasPrefix("lo"), !bsd.hasPrefix("utun"), !bsd.hasPrefix("llw"), !bsd.hasPrefix("awdl"), !bsd.hasPrefix("ipsec"), !bsd.hasPrefix("anpi") else { continue }

                let rawName = (SCNetworkInterfaceGetLocalizedDisplayName(iface) as String?) ?? bsd
                let type = SCNetworkInterfaceGetInterfaceType(iface) as String?
                let mac = SCNetworkInterfaceGetHardwareAddressString(iface) as String?
                let kind = classifyInterface(hardwarePortName: rawName, bsdName: bsd, scType: type)
                results.append(DiscoveredAdapter(bsdName: bsd, displayName: rawName, kind: kind, macAddress: mac))
            }
        }

        return results
    }

    private static func queryDynamicStoreLinkStates(store: SCDynamicStore?) -> [String: Bool] {
        guard let store = store else { return [:] }
        var result: [String: Bool] = [:]
        if let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Interface/.*/Link" as CFString) as? [String] {
            for key in keys {
                let parts = key.components(separatedBy: "/")
                guard parts.count >= 4 else { continue }
                let bsd = parts[3]
                if let dict = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
                   let active = dict["Active"] as? Int {
                    result[bsd] = (active == 1)
                }
            }
        }
        return result
    }

    public static func isVirtualInterface(bsdName: String) -> Bool {
        let lower = bsdName.lowercased()
        let virtualPrefixes = ["lo", "utun", "llw", "awdl", "ipsec", "anpi", "vmnet", "gif", "stf", "bridge"]
        for prefix in virtualPrefixes {
            if lower.hasPrefix(prefix) { return true }
        }
        return false
    }

    public static func isInterfaceMetered(kind: PowerloadInterfaceKind, portName: String, bsdName: String) -> Bool {
        if kind == .usb { return true }
        let lower = portName.lowercased()
        if lower.contains("iphone") || lower.contains("ipad") || lower.contains("cellular") || lower.contains("tether") || lower.contains("hotspot") || lower.contains("rndis") {
            return true
        }
        return false
    }

    public static func initialHealth(hasIPv4: Bool, isLinkActive: Bool, gatewayIP: String?) -> PowerloadHealthState {
        if !isLinkActive {
            return .unusable(reason: "Physical link down")
        }
        if !hasIPv4 {
            return .unusable(reason: "No IPv4 address assigned")
        }
        if gatewayIP == nil {
            return .degraded(reason: "No default gateway (link-local)")
        }
        return .usable
    }

    private static func queryGatewayIPs(store: SCDynamicStore?) -> [String: String] {
        guard let store = store else { return [:] }
        var result: [String: String] = [:]

        // 1. Check State:/Network/Service/.*/IPv4 for per-interface routers
        if let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Service/.*/IPv4" as CFString) as? [String] {
            for key in keys {
                if let dict = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any] {
                    let ifName = (dict["InterfaceName"] as? String) ?? (dict["ConfirmedInterfaceName"] as? String)
                    let router = dict["Router"] as? String
                    if let ifName = ifName, let router = router, !router.isEmpty {
                        result[ifName] = router
                    }
                }
            }
        }

        // 2. Check State:/Network/Global/IPv4 for the primary interface default router
        if let globalDict = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
           let primaryIf = globalDict["PrimaryInterface"] as? String,
           let router = globalDict["Router"] as? String,
           !router.isEmpty {
            if result[primaryIf] == nil {
                result[primaryIf] = router
            }
        }

        return result
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
            guard !name.hasPrefix("lo"), !name.hasPrefix("utun"), !name.hasPrefix("llw"), !name.hasPrefix("awdl"), !name.hasPrefix("ipsec"), !name.hasPrefix("anpi") else { continue }
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
                // Language-agnostic parser: splits into blocks separated by empty lines.
                // Each valid block has key: value lines where line 1 is Port Name, line 2 is Device.
                let blocks = output.components(separatedBy: "\n\n")
                for block in blocks {
                    let lines = block.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { $0.contains(":") }
                    
                    var portName: String?
                    var deviceName: String?
                    for line in lines {
                        let parts = line.components(separatedBy: ":")
                        guard parts.count >= 2 else { continue }
                        let key = parts[0].lowercased()
                        let val = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                        if key.contains("port") || key.contains("hardware") || key.contains("matériel") {
                            portName = val
                        } else if key.contains("device") || key.contains("appareil") || key.contains("gerät") {
                            deviceName = val
                        }
                    }
                    if let port = portName, let device = deviceName, !device.isEmpty {
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

    private static func classifyInterface(hardwarePortName: String, bsdName: String, scType: String? = nil) -> PowerloadInterfaceKind {
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
        if name.contains("ethernet") || name.contains("lan") || name.contains("thunderbolt") || name.contains("ax88") || name.contains("realtek") {
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

// MARK: - Backward Compatibility Typealias
public typealias PlexoNetworkManager = PowerloadNetworkManager
