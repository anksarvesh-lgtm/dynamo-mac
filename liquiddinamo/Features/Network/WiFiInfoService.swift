//
//  WiFiInfoService.swift
//  boringNotch
//
//  Created for Boring Notch
//

import Combine
import CoreLocation
import CoreWLAN
import Darwin
import Foundation
import SwiftUI

// MARK: - Enums & Models

/// Channel frequency band for Wi-Fi.
public enum WiFiChannelBand: String, CaseIterable, Identifiable, Sendable {
    case band2GHz = "2.4 GHz"
    case band5GHz = "5 GHz"
    case band6GHz = "6 GHz"
    case unknown = "Unknown"

    public var id: String { rawValue }
    public var displayName: String { rawValue }

    public init(cwBand: CWChannelBand) {
        switch cwBand {
        case .band2GHz:
            self = .band2GHz
        case .band5GHz:
            self = .band5GHz
        case .band6GHz:
            self = .band6GHz
        case .bandUnknown:
            self = .unknown
        @unknown default:
            self = .unknown
        }
    }
}

/// Channel bandwidth in MHz.
public enum WiFiChannelWidth: String, CaseIterable, Identifiable, Sendable {
    case width20MHz = "20 MHz"
    case width40MHz = "40 MHz"
    case width80MHz = "80 MHz"
    case width160MHz = "160 MHz"
    case unknown = "Unknown"

    public var id: String { rawValue }
    public var displayName: String { rawValue }

    public init(cwWidth: CWChannelWidth) {
        switch cwWidth {
        case .width20MHz:
            self = .width20MHz
        case .width40MHz:
            self = .width40MHz
        case .width80MHz:
            self = .width80MHz
        case .width160MHz:
            self = .width160MHz
        case .widthUnknown:
            self = .unknown
        @unknown default:
            self = .unknown
        }
    }
}

/// Wi-Fi Security Protocol.
public enum WiFiSecurityType: String, CaseIterable, Identifiable, Sendable {
    case none = "Open"
    case wep = "WEP"
    case wpaPersonal = "WPA Personal"
    case wpaPersonalMixed = "WPA/WPA2 Personal"
    case wpa2Personal = "WPA2 Personal"
    case personal = "Personal"
    case dynamicWEP = "Dynamic WEP"
    case wpaEnterprise = "WPA Enterprise"
    case wpaEnterpriseMixed = "WPA/WPA2 Enterprise"
    case wpa2Enterprise = "WPA2 Enterprise"
    case enterprise = "Enterprise"
    case wpa3Personal = "WPA3 Personal"
    case wpa3Enterprise = "WPA3 Enterprise"
    case wpa3Transition = "WPA3 Transition"
    case owe = "OWE (Enhanced Open)"
    case unknown = "Unknown"

    public var id: String { rawValue }
    public var displayName: String { rawValue }

    public init(cwSecurity: CWSecurity) {
        switch cwSecurity {
        case .none:
            self = .none
        case .WEP:
            self = .wep
        case .wpaPersonal:
            self = .wpaPersonal
        case .wpaPersonalMixed:
            self = .wpaPersonalMixed
        case .wpa2Personal:
            self = .wpa2Personal
        case .personal:
            self = .personal
        case .dynamicWEP:
            self = .dynamicWEP
        case .wpaEnterprise:
            self = .wpaEnterprise
        case .wpaEnterpriseMixed:
            self = .wpaEnterpriseMixed
        case .wpa2Enterprise:
            self = .wpa2Enterprise
        case .enterprise:
            self = .enterprise
        case .wpa3Personal:
            self = .wpa3Personal
        case .wpa3Enterprise:
            self = .wpa3Enterprise
        case .wpa3Transition:
            self = .wpa3Transition
        case .OWE, .oweTransition:
            self = .owe
        case .unknown:
            self = .unknown
        @unknown default:
            self = .unknown
        }
    }
}

/// 802.11 Physical Layer (PHY) standard.
public enum WiFiPHYMode: String, CaseIterable, Identifiable, Sendable {
    case mode11a = "802.11a"
    case mode11b = "802.11b"
    case mode11g = "802.11g"
    case mode11n = "Wi-Fi 4 (802.11n)"
    case mode11ac = "Wi-Fi 5 (802.11ac)"
    case mode11ax = "Wi-Fi 6 (802.11ax)"
    case mode11be = "Wi-Fi 7 (802.11be)"
    case none = "None"
    case unknown = "Unknown"

    public var id: String { rawValue }

    public init(cwPHYMode: CWPHYMode) {
        switch cwPHYMode {
        case .mode11a:
            self = .mode11a
        case .mode11b:
            self = .mode11b
        case .mode11g:
            self = .mode11g
        case .mode11n:
            self = .mode11n
        case .mode11ac:
            self = .mode11ac
        case .mode11ax:
            self = .mode11ax
        case .mode11be:
            self = .mode11be
        case .modeNone:
            self = .none
        @unknown default:
            self = .unknown
        }
    }
}

/// Comprehensive Wi-Fi connection metadata model.
public struct WiFiNetworkInfo: Equatable, Sendable {
    /// SSID (Network Name). On macOS 14+, requires Location Services authorization; nil if unauthorized or hidden.
    public let ssid: String?
    /// BSSID (Access Point MAC address).
    public let bssid: String?
    /// Received Signal Strength Indicator in dBm (e.g. -55).
    public let rssi: Int
    /// Ambient noise floor measurement in dBm (e.g. -90).
    public let noise: Int
    /// Signal-to-Noise Ratio in dB (rssi - noise).
    public let signalToNoiseRatio: Int
    /// Operating channel number (e.g. 157 or 36).
    public let channelNumber: Int
    /// Channel frequency band (2.4 GHz, 5 GHz, 6 GHz).
    public let channelBand: WiFiChannelBand
    /// Channel bandwidth (20, 40, 80, 160 MHz).
    public let channelWidth: WiFiChannelWidth
    /// Current transmit data rate in Mbps (e.g. 433.0 or 866.0).
    public let transmitRate: Double
    /// Wi-Fi Security Protocol (e.g. WPA2 Personal, WPA3 Personal).
    public let securityType: WiFiSecurityType
    /// 802.11 PHY generation mode (e.g. Wi-Fi 5, Wi-Fi 6).
    public let phyMode: WiFiPHYMode
    /// Local IPv4 address assigned to this Wi-Fi interface (e.g. "192.168.29.150").
    public let localIPv4: String?
    /// Name of the primary wireless hardware interface (e.g. "en0").
    public let interfaceName: String
    /// True if the connection is identified as an iPhone/Android Personal Hotspot.
    public let isHotspot: Bool

    public init(
        ssid: String?,
        bssid: String?,
        rssi: Int,
        noise: Int,
        signalToNoiseRatio: Int,
        channelNumber: Int,
        channelBand: WiFiChannelBand,
        channelWidth: WiFiChannelWidth,
        transmitRate: Double,
        securityType: WiFiSecurityType,
        phyMode: WiFiPHYMode,
        localIPv4: String?,
        interfaceName: String,
        isHotspot: Bool
    ) {
        self.ssid = ssid
        self.bssid = bssid
        self.rssi = rssi
        self.noise = noise
        self.signalToNoiseRatio = signalToNoiseRatio
        self.channelNumber = channelNumber
        self.channelBand = channelBand
        self.channelWidth = channelWidth
        self.transmitRate = transmitRate
        self.securityType = securityType
        self.phyMode = phyMode
        self.localIPv4 = localIPv4
        self.interfaceName = interfaceName
        self.isHotspot = isHotspot
    }

    // MARK: - Presentation Helpers

    /// Display title for the network: actual SSID or "Network name hidden".
    public var displayName: String {
        if let s = ssid, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return s
        }
        return "Network name hidden"
    }

    /// Signal strength level normalized to 0...4 bars.
    public var signalBars: Int {
        if rssi >= -55 { return 4 }
        if rssi >= -67 { return 3 }
        if rssi >= -78 { return 2 }
        if rssi >= -88 { return 1 }
        return 0
    }

    /// Descriptive qualitative rating of connection strength.
    public var signalQualityDescription: String {
        switch signalBars {
        case 4: return "Excellent"
        case 3: return "Good"
        case 2: return "Fair"
        case 1: return "Weak"
        default: return "Very Poor"
        }
    }

    /// Formatted channel summary: e.g. "157 (5 GHz, 80 MHz)".
    public var formattedChannel: String {
        "\(channelNumber) (\(channelBand.rawValue), \(channelWidth.rawValue))"
    }

    /// Formatted transmit rate string: e.g. "433 Mbps".
    public var formattedTransmitRate: String {
        if transmitRate > 0 {
            return "\(Int(transmitRate)) Mbps"
        }
        return "–"
    }

    /// Formatted signal details string: e.g. "-55 dBm (Noise: -90 dBm, SNR: 35 dB)".
    public var formattedSignalDetails: String {
        "\(rssi) dBm (Noise: \(noise) dBm, SNR: \(signalToNoiseRatio) dB)"
    }
}

/// Overall Wi-Fi connection and interface state.
public enum WiFiConnectionState: Equatable {
    /// Mac has no wireless network card (e.g. desktop Mac on Ethernet only).
    case noInterface
    /// Wi-Fi hardware is present but powered off.
    case wifiOff(interfaceName: String)
    /// Wi-Fi is on, but currently disconnected / not associated with a network.
    case disconnected(interfaceName: String)
    /// Associated and connected to a Wi-Fi network.
    case connected(WiFiNetworkInfo)
}

// MARK: - Wi-Fi Info Service

/// Observable singleton service providing real-time Wi-Fi telemetry via CoreWLAN and Location Services.
///
/// Features:
/// - Event-driven updates via `CWEventDelegate` with zero continuous polling.
/// - Active lifecycle monitoring: runs slow 3-second live metric refreshes only while the tab is visible.
/// - Graceful handling of macOS 14+ Location Services privacy (SSID hidden without crashing).
/// - Detection of Wi-Fi disabled state, missing hardware interfaces, and Personal Hotspots.
@MainActor
public final class WiFiInfoService: NSObject, ObservableObject {
    public static let shared = WiFiInfoService()

    // MARK: - Published State

    @Published public private(set) var state: WiFiConnectionState = .noInterface
    @Published public private(set) var currentInfo: WiFiNetworkInfo? = nil
    @Published public private(set) var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published public private(set) var isTabVisible: Bool = false

    // MARK: - Internal Dependencies

    private let wifiClient: CWWiFiClient
    private var locationManager: CLLocationManager?
    private var eventDelegateBridge: WiFiEventBridge?
    private var slowRefreshTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.agrigence.liquiddynamo.wifi", qos: .utility)

    // MARK: - Initialization

    private override init() {
        self.wifiClient = CWWiFiClient.shared()
        super.init()

        // Read initial location authorization without requesting it
        let lm = CLLocationManager()
        self.locationAuthorizationStatus = lm.authorizationStatus
        self.locationManager = lm

        // Set up bridge for CoreWLAN events
        let bridge = WiFiEventBridge { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.isTabVisible else { return }
                self.refresh()
            }
        }
        self.eventDelegateBridge = bridge
        self.wifiClient.delegate = bridge

        // Configure location delegate
        let locDelegate = LocationDelegateBridge { [weak self] newStatus in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.locationAuthorizationStatus = newStatus
                // If location was just authorized, immediately refresh Wi-Fi info to obtain SSID
                if newStatus == .authorizedAlways {
                    self.refresh()
                }
            }
        }
        lm.delegate = locDelegate
        objc_setAssociatedObject(lm, "bridge", locDelegate, .OBJC_ASSOCIATION_RETAIN)

        // Perform initial baseline read
        refresh()
    }

    deinit {
        try? wifiClient.stopMonitoringAllEvents()
        slowRefreshTimer?.cancel()
    }

    // MARK: - Computed Properties

    public var isConnected: Bool {
        if case .connected = state {
            return true
        }
        return false
    }

    /// Indicates whether Location Services is authorized for SSID discovery.
    public var isLocationAuthorized: Bool {
        locationAuthorizationStatus == .authorizedAlways
    }

    /// Indicates whether the network name is hidden due to missing Location authorization.
    public var needsLocationAuthorization: Bool {
        guard let info = currentInfo else { return false }
        let hasNoSSID = (info.ssid == nil || info.ssid?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true)
        return hasNoSSID && locationAuthorizationStatus != .authorizedAlways
    }

    /// Indicates whether the app can trigger the system prompt (only when .notDetermined).
    public var canRequestLocationAuthorization: Bool {
        locationAuthorizationStatus == .notDetermined
    }

    // MARK: - Tab Visibility & Lifecycle Control

    /// Called by the Network Tab or View when appearing / disappearing.
    /// - `true`: Refreshes values, starts event monitoring, and starts a slow 3-second live RF timer.
    /// - `false`: Stops event monitoring and cancels all background timers to consume 0% CPU.
    public func setTabVisible(_ visible: Bool) {
        guard isTabVisible != visible else { return }
        isTabVisible = visible

        if visible {
            refresh()
            startEventMonitoring()
            startSlowRefreshTimer()
        } else {
            stopEventMonitoring()
            stopSlowRefreshTimer()
        }
    }

    // MARK: - Telemetry Sampling

    /// Refreshes all Wi-Fi telemetry fields synchronously from CoreWLAN and network interfaces.
    public func refresh() {
        guard let interface = wifiClient.interface() else {
            // Check if there are any interfaces listed
            let names = wifiClient.interfaceNames() ?? []
            if names.isEmpty {
                self.state = .noInterface
                self.currentInfo = nil
                return
            }
            // If primary is nil, attempt the first named interface
            guard let first = names.first, let iface = wifiClient.interface(withName: first) else {
                self.state = .noInterface
                self.currentInfo = nil
                return
            }
            update(with: iface)
            return
        }

        update(with: interface)
    }

    private func update(with interface: CWInterface) {
        let ifName = interface.interfaceName ?? "en0"

        // 1. Check Wi-Fi Power State
        guard interface.powerOn() else {
            self.state = .wifiOff(interfaceName: ifName)
            self.currentInfo = nil
            return
        }

        // 2. Read RF & Association properties
        let channel = interface.wlanChannel()
        let rssi = interface.rssiValue()
        let noise = interface.noiseMeasurement()
        let txRate = interface.transmitRate()
        let rawSSID = interface.ssid()
        let rawBSSID = interface.bssid()

        // If there is no channel and RSSI/TxRate are 0, device is disconnected / searching
        if channel == nil && rssi == 0 && txRate == 0 && rawSSID == nil {
            self.state = .disconnected(interfaceName: ifName)
            self.currentInfo = nil
            return
        }

        // Calculate Signal-to-Noise Ratio (dB)
        let snr = rssi - noise

        // Map Channel parameters
        let chNumber = channel?.channelNumber ?? 0
        let chBand = WiFiChannelBand(cwBand: channel?.channelBand ?? .bandUnknown)
        let chWidth = WiFiChannelWidth(cwWidth: channel?.channelWidth ?? .widthUnknown)

        // Map Security & PHY Mode
        let security = WiFiSecurityType(cwSecurity: interface.security())
        let phy = WiFiPHYMode(cwPHYMode: interface.activePHYMode())

        // Fetch Local IPv4 address
        let localIP = fetchLocalIPv4(for: ifName)

        // Hotspot connection detection
        let hotspot = detectHotspot(interface: interface, localIP: localIP)

        let info = WiFiNetworkInfo(
            ssid: rawSSID,
            bssid: rawBSSID,
            rssi: rssi,
            noise: noise,
            signalToNoiseRatio: snr,
            channelNumber: chNumber,
            channelBand: chBand,
            channelWidth: chWidth,
            transmitRate: txRate,
            securityType: security,
            phyMode: phy,
            localIPv4: localIP,
            interfaceName: ifName,
            isHotspot: hotspot
        )

        self.currentInfo = info
        self.state = .connected(info)
    }

    // MARK: - Location Services Authorization

    /// Requests Location authorization via CLLocationManager.
    /// Strictly called ONLY when user taps "Allow network name", NEVER automatically on launch.
    public func requestLocationAuthorization() {
        guard let lm = locationManager else { return }

        // Update cached status
        self.locationAuthorizationStatus = lm.authorizationStatus

        if lm.authorizationStatus == .notDetermined {
            lm.requestWhenInUseAuthorization()
        } else if lm.authorizationStatus == .denied || lm.authorizationStatus == .restricted {
            openSystemLocationSettings()
        }
    }

    /// Directs user to macOS System Settings > Privacy & Security > Location Services if previously denied.
    public func openSystemLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - CoreWLAN Event Monitoring

    private func startEventMonitoring() {
        do {
            try wifiClient.startMonitoringEvent(with: .ssidDidChange)
            try wifiClient.startMonitoringEvent(with: .bssidDidChange)
            try wifiClient.startMonitoringEvent(with: .linkDidChange)
            try wifiClient.startMonitoringEvent(with: .linkQualityDidChange)
            try wifiClient.startMonitoringEvent(with: .powerDidChange)
            try wifiClient.startMonitoringEvent(with: .modeDidChange)
        } catch {
            // Non-critical: slow refresh timer will still provide fallback
        }
    }

    private func stopEventMonitoring() {
        try? wifiClient.stopMonitoringAllEvents()
    }

    // MARK: - Slow Refresh Timer (3s while visible)

    private func startSlowRefreshTimer() {
        stopSlowRefreshTimer()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 3.0, repeating: 3.0, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.isTabVisible else { return }
                self.refresh()
            }
        }
        timer.resume()
        self.slowRefreshTimer = timer
    }

    private func stopSlowRefreshTimer() {
        slowRefreshTimer?.cancel()
        slowRefreshTimer = nil
    }

    // MARK: - Network Helpers

    /// Queries local IPv4 address of the Wi-Fi interface using getifaddrs.
    private func fetchLocalIPv4(for interfaceName: String) -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let name = String(cString: ptr.pointee.ifa_name)
            guard name == interfaceName else { continue }
            let family = ptr.pointee.ifa_addr.pointee.sa_family
            if family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    ptr.pointee.ifa_addr,
                    socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    return String(cString: hostname)
                }
            }
        }
        return nil
    }

    /// Identifies whether the current connection is a cellular/personal mobile hotspot.
    private func detectHotspot(interface: CWInterface, localIP: String?) -> Bool {
        // 1. iOS Personal Hotspot standard DHCP subnet is 172.20.10.0/28
        if let ip = localIP, ip.hasPrefix("172.20.10.") {
            return true
        }
        // 2. Android Mobile Hotspot default subnet is 192.168.43.0/24
        if let ip = localIP, ip.hasPrefix("192.168.43.") {
            return true
        }
        // 3. Check SSID device naming indicators
        if let ssid = interface.ssid()?.lowercased() {
            if ssid.contains("iphone") || ssid.contains("ipad") || ssid.contains("hotspot") || ssid.contains("pixel") {
                return true
            }
        }
        return false
    }
}

// MARK: - Internal Delegate Bridges

/// Internal CWEventDelegate bridge relaying CoreWLAN notifications to WiFiInfoService.
private final class WiFiEventBridge: NSObject, CWEventDelegate, @unchecked Sendable {
    private let onEvent: @Sendable () -> Void

    init(onEvent: @escaping @Sendable () -> Void) {
        self.onEvent = onEvent
    }

    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        onEvent()
    }

    func bssidDidChangeForWiFiInterface(withName interfaceName: String) {
        onEvent()
    }

    func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        onEvent()
    }

    func linkQualityDidChangeForWiFiInterface(withName interfaceName: String, rssi: Int, transmitRate: Double) {
        onEvent()
    }

    func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        onEvent()
    }

    func modeDidChangeForWiFiInterface(withName interfaceName: String) {
        onEvent()
    }
}

/// Internal CLLocationManagerDelegate bridge relaying authorization changes.
private final class LocationDelegateBridge: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let onAuthChanged: @Sendable (CLAuthorizationStatus) -> Void

    init(onAuthChanged: @escaping @Sendable (CLAuthorizationStatus) -> Void) {
        self.onAuthChanged = onAuthChanged
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthChanged(manager.authorizationStatus)
    }
}
