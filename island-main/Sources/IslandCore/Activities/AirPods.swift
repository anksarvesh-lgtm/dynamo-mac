import Foundation

/// AirPods / Beats models Island can identify, from the Bluetooth product ID (Apple vendor 0x004C)
/// or, failing that, the device name.
public enum AirPodsModel: String, CaseIterable, Sendable, Codable {
    case airPods1, airPods2, airPods3, airPods4, airPods4ANC
    case airPodsPro, airPodsPro2, airPodsPro2USBC, airPodsPro3
    case airPodsMax, airPodsMaxUSBC
    case unknownAirPods

    public var displayName: String {
        switch self {
        case .airPods1, .airPods2, .airPods3, .unknownAirPods: "AirPods"
        case .airPods4: "AirPods 4"
        case .airPods4ANC: "AirPods 4"
        case .airPodsPro, .airPodsPro2, .airPodsPro2USBC, .airPodsPro3: "AirPods Pro"
        case .airPodsMax, .airPodsMaxUSBC: "AirPods Max"
        }
    }

    /// Over-ear models report one battery; earbuds report left, right and case.
    public var isOverEar: Bool { self == .airPodsMax || self == .airPodsMaxUSBC }

    /// File stem for an optional bundled product render (`Resources/AirPods/<stem>.png`), most specific first.
    public var artworkNames: [String] {
        switch self {
        case .airPodsPro2, .airPodsPro2USBC: [rawValue, "airPodsPro2", "airPodsPro"]
        case .airPodsPro3: [rawValue, "airPodsPro2", "airPodsPro"]
        case .airPodsMaxUSBC: [rawValue, "airPodsMax"]
        case .airPods4ANC: [rawValue, "airPods4"]
        default: [rawValue]
        }
    }

    /// Known Apple product IDs. Unlisted IDs fall back to name matching.
    static let productIDs: [Int: AirPodsModel] = [
        0x2002: .airPods1, 0x200F: .airPods2, 0x2013: .airPods3,
        0x200E: .airPodsPro, 0x2014: .airPodsPro2, 0x2024: .airPodsPro2USBC, 0x2027: .airPodsPro3,
        0x200A: .airPodsMax, 0x201F: .airPodsMaxUSBC,
        0x2019: .airPods4, 0x201B: .airPods4ANC,
    ]

    public static func resolve(productID: Int?, name: String) -> AirPodsModel? {
        if let pid = productID, let m = productIDs[pid] { return m }
        let n = name.lowercased()
        guard n.contains("airpods") else { return nil }
        if n.contains("max") { return .airPodsMax }
        if n.contains("pro") { return .airPodsPro2 }
        return .unknownAirPods
    }

    /// `com.apple.device-model-code` tag macOS uses for the model's device type (e.g. "Device1,8228").
    public static func deviceModelCode(productID: Int) -> String { "Device1,\(productID)" }
}

/// Battery levels in percent; nil when the device doesn't report that component.
public struct AirPodsBattery: Equatable, Sendable, Codable {
    public var left: Int?
    public var right: Int?
    public var caseLevel: Int?
    /// Over-ear headphones report a single level.
    public var single: Int?

    public init(left: Int? = nil, right: Int? = nil, caseLevel: Int? = nil, single: Int? = nil) {
        self.left = left.map(Self.clamp)
        self.right = right.map(Self.clamp)
        self.caseLevel = caseLevel.map(Self.clamp)
        self.single = single.map(Self.clamp)
    }

    public var isEmpty: Bool { left == nil && right == nil && caseLevel == nil && single == nil }

    /// The level to headline: the lower earbud (what runs out first), or the single level.
    public var headline: Int? {
        if let single { return single }
        switch (left, right) {
        case let (l?, r?): return min(l, r)
        case let (l?, nil): return l
        case let (nil, r?): return r
        default: return caseLevel
        }
    }

    static func clamp(_ v: Int) -> Int { min(100, max(0, v)) }
}

/// What Apple's `system_profiler SPBluetoothDataType -json` reports for one device.
public struct BluetoothDeviceReport: Equatable, Sendable {
    public var name: String
    public var address: String?
    public var productID: Int?
    public var vendorID: Int?
    public var connected: Bool
    public var battery: AirPodsBattery

    public init(name: String, address: String? = nil, productID: Int? = nil, vendorID: Int? = nil,
                connected: Bool, battery: AirPodsBattery = AirPodsBattery()) {
        self.name = name
        self.address = address
        self.productID = productID
        self.vendorID = vendorID
        self.connected = connected
        self.battery = battery
    }
}

/// Parses `system_profiler SPBluetoothDataType -json` — Apple's supported, public reporting tool.
public enum SystemProfilerBluetoothParser {
    public static func parse(_ data: Data) -> [BluetoothDeviceReport] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var out: [BluetoothDeviceReport] = []
        for controller in controllers {
            for (section, connected) in [("device_connected", true), ("device_not_connected", false)] {
                for entry in controller[section] as? [[String: Any]] ?? [] {
                    for (name, value) in entry {
                        guard let info = value as? [String: Any] else { continue }
                        out.append(BluetoothDeviceReport(
                            name: name,
                            address: info["device_address"] as? String,
                            productID: hex(info["device_productID"]),
                            vendorID: hex(info["device_vendorID"]),
                            connected: connected,
                            battery: AirPodsBattery(
                                left: percent(info["device_batteryLevelLeft"]),
                                right: percent(info["device_batteryLevelRight"]),
                                caseLevel: percent(info["device_batteryLevelCase"]),
                                single: percent(info["device_batteryLevelMain"]) ?? percent(info["device_batteryLevel"]))))
                    }
                }
            }
        }
        return out
    }

    /// "0x2024" → 8228
    static func hex(_ v: Any?) -> Int? {
        guard let s = v as? String else { return nil }
        let t = s.lowercased().hasPrefix("0x") ? String(s.dropFirst(2)) : s
        return Int(t, radix: 16)
    }

    /// "80%" or 80 → 80
    static func percent(_ v: Any?) -> Int? {
        if let n = v as? Int { return n }
        guard let s = v as? String else { return nil }
        return Int(s.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
    }

    /// Best match for an audio route name ("Poshak’s AirPods Pro"), tolerant of apostrophe/space variants.
    public static func match(_ name: String, in reports: [BluetoothDeviceReport]) -> BluetoothDeviceReport? {
        func norm(_ s: String) -> String {
            s.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        let n = norm(name)
        return reports.first { norm($0.name) == n && $0.connected }
            ?? reports.first { norm($0.name) == n }
            ?? reports.first { $0.connected && (norm($0.name).contains(n) || n.contains(norm($0.name))) }
    }
}

/// The AirPods connection sequence as a pure state machine.
///
/// idle → detecting → expanding → revealingDevice → connected → dismissing → idle
///
/// Timing lives in `AirPodsConnectionAnimator` (app layer); this type only decides transitions, so the
/// sequence can be unit-tested and can't skip or repeat a phase.
public enum AirPodsConnectionPhase: String, Equatable, Sendable, CaseIterable {
    case idle, detecting, expanding, revealingDevice, connected, dismissing

    /// Phases in which the Island is open showing the card.
    public var isPresenting: Bool { self == .expanding || self == .revealingDevice || self == .connected }
}

public enum AirPodsConnectionEvent: Equatable, Sendable {
    /// A new AirPods connection was seen.
    case deviceConnected
    /// Model/battery details resolved (or gave up) — ready to open.
    case detailsReady
    /// The Island finished opening.
    case islandOpened
    /// The artwork entrance finished.
    case revealFinished
    /// The hold time elapsed (or the user dismissed).
    case holdElapsed
    /// The Island finished closing.
    case islandClosed
    /// The device went away mid-sequence.
    case deviceDisconnected
}

public struct AirPodsConnectionStateMachine: Equatable, Sendable {
    public private(set) var phase: AirPodsConnectionPhase = .idle

    public init() {}

    @discardableResult
    public mutating func handle(_ event: AirPodsConnectionEvent) -> AirPodsConnectionPhase {
        switch (phase, event) {
        case (.idle, .deviceConnected): phase = .detecting
        case (.detecting, .detailsReady): phase = .expanding
        case (.expanding, .islandOpened): phase = .revealingDevice
        case (.revealingDevice, .revealFinished): phase = .connected
        case (.connected, .holdElapsed), (.revealingDevice, .holdElapsed), (.expanding, .holdElapsed): phase = .dismissing
        case (.dismissing, .islandClosed): phase = .idle
        case (.detecting, .deviceDisconnected): phase = .idle
        case (.expanding, .deviceDisconnected), (.revealingDevice, .deviceDisconnected), (.connected, .deviceDisconnected):
            phase = .dismissing
        default: break // Ignore out-of-order events: a phase can never be skipped or repeated.
        }
        return phase
    }
}
