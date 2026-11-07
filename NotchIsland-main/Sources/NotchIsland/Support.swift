import AppKit
import Combine
import SwiftUI
import IOKit.pwr_mgt

// MARK: - Settings

/// A UserDefaults-backed property on an ObservableObject that publishes changes.
@propertyWrapper
struct Pref<Value> {
    let key: String
    let defaultValue: Value
    init(_ key: String, _ defaultValue: Value) { self.key = key; self.defaultValue = defaultValue }

    static subscript<T: ObservableObject>(
        _enclosingInstance instance: T,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
    ) -> Value where T.ObjectWillChangePublisher == ObservableObjectPublisher {
        get {
            let w = instance[keyPath: storageKeyPath]
            return UserDefaults.standard.object(forKey: w.key) as? Value ?? w.defaultValue
        }
        set {
            instance.objectWillChange.send()
            let w = instance[keyPath: storageKeyPath]
            UserDefaults.standard.set(newValue, forKey: w.key)
        }
    }

    @available(*, unavailable, message: "Pref only works inside an ObservableObject")
    var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // General
    @Pref("showMenuBarIcon", true) var showMenuBarIcon: Bool
    @Pref("hoverDelay", 0.12) var hoverDelay: Double
    @Pref("haptics", true) var haptics: Bool
    @Pref("sounds", false) var sounds: Bool
    @Pref("accentHex", "#FFFFFF") var accentHex: String
    @Pref("translucentShade", false) var translucentShade: Bool
    @Pref("islandShadow", true) var islandShadow: Bool                     // a window's shadow under the open island
    @Pref("hotkeyKeyCode", 49) var hotkeyKeyCode: Int                       // Space
    @Pref("hotkeyModifiers", 524288) var hotkeyModifiers: Int                // ⌥ (NSEvent.ModifierFlags.option)

    // Modules
    @Pref("mediaEnabled", true) var mediaEnabled: Bool
    @Pref("notificationsEnabled", true) var notificationsEnabled: Bool
    @Pref("calendarEnabled", true) var calendarEnabled: Bool
    @Pref("timerEnabled", true) var timerEnabled: Bool
    @Pref("clipboardEnabled", true) var clipboardEnabled: Bool
    @Pref("downloadsEnabled", true) var downloadsEnabled: Bool
    @Pref("shelfEnabled", true) var shelfEnabled: Bool
    @Pref("indicatorsEnabled", true) var indicatorsEnabled: Bool           // mic / camera / focus
    @Pref("bluetoothEnabled", true) var bluetoothEnabled: Bool
    @Pref("batteryAlertsEnabled", true) var batteryAlertsEnabled: Bool
    @Pref("volumeHUDEnabled", true) var volumeHUDEnabled: Bool
    @Pref("quickTogglesEnabled", true) var quickTogglesEnabled: Bool

    // Visibility
    @Pref("hideInFullscreen", false) var hideInFullscreen: Bool
    @Pref("hiddenApps", "") var hiddenApps: String                          // comma-separated bundle ids

    // Updates (Settings ▸ Updates, see Updater.swift)
    @Pref("updatesAutoCheck", true) var updatesAutoCheck: Bool              // ask GitHub once a day
    @Pref("updatesNotify", true) var updatesNotify: Bool                    // HUD in the island when one is found
    @Pref("updatesSkippedVersion", "") var updatesSkippedVersion: String
    @Pref("updatesLastCheck", 0.0) var updatesLastCheck: Double             // timeIntervalSince1970

    var hiddenAppIDs: Set<String> {
        Set(hiddenApps.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    var hotkeyFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(hotkeyModifiers)).intersection(.deviceIndependentFlagsMask)
    }

    var hotkeyDescription: String {
        Hotkey.describe(keyCode: hotkeyKeyCode, flags: hotkeyFlags)
    }
}

// MARK: - Theme, motion, feedback

enum Theme {
    static var accent: Color { Color(hex: AppSettings.shared.accentHex) ?? .white }
    static var accentNS: NSColor { NSColor(hex: AppSettings.shared.accentHex) ?? .white }
    /// Black or white, whichever reads on the accent colour.
    static var onAccent: Color { on(accentNS) }
    static func on(_ color: Color) -> Color { on(NSColor(color)) }
    static func on(_ color: NSColor) -> Color {
        guard let c = color.usingColorSpace(.sRGB) else { return .black }
        let luminance = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        return luminance > 0.55 ? .black : .white
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}

extension Color {
    init?(hex: String) {
        guard let ns = NSColor(hex: hex) else { return nil }
        self.init(nsColor: ns)
    }
}

enum Motion {
    static var reduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var spring: Animation { reduce ? .easeInOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.78) }
    static var quick: Animation { reduce ? .easeInOut(duration: 0.1) : .spring(response: 0.3, dampingFraction: 0.85) }
}

enum Feedback {
    static func tap() {
        let s = AppSettings.shared
        if s.haptics { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        if s.sounds { NSSound(named: "Pop")?.play() }
    }
    static func alert() {
        let s = AppSettings.shared
        if s.haptics { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
        if s.sounds { NSSound(named: "Glass")?.play() }
    }
    /// Timer finished etc. — always audible, this is the point of the feature.
    static func chime() { NSSound(named: "Glass")?.play() }
}

// MARK: - Launch at login

/// A bare executable can't use SMAppService, so this installs a LaunchAgent pointing at the
/// current binary. If the binary moves (e.g. a rebuild in a different folder), re-enable it.
enum LaunchAtLogin {
    static let label = "com.notchisland.app"
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    static func set(_ enabled: Bool) {
        let domain = "gui/\(getuid())"
        if enabled {
            guard let exe = Bundle.main.executablePath else { return }
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [exe],
                "RunAtLoad": true,
                "KeepAlive": false,
                "ProcessType": "Interactive",
            ]
            try? FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                try? data.write(to: plistURL)
            }
            _ = QuickSystem.run("/bin/launchctl", ["bootstrap", domain, plistURL.path])
        } else {
            _ = QuickSystem.run("/bin/launchctl", ["bootout", "\(domain)/\(label)"])
            try? FileManager.default.removeItem(at: plistURL)
        }
    }
}

// MARK: - System quick actions

enum QuickSystem {
    @discardableResult
    static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        do { try p.run() } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func runAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var err: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&err)
        }
    }

    /// Quits and starts the app again. macOS applies a new Full Disk Access grant only to a fresh process.
    /// When launchd started us (launch at login), the job is restarted in place; starting a second
    /// copy with `open -n` would leave launchd's job empty and later launches would double up.
    static func relaunch() {
        if ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == LaunchAtLogin.label {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            p.arguments = ["kickstart", "-k", "gui/\(getuid())/\(LaunchAtLogin.label)"]
            if (try? p.run()) != nil {
                p.waitUntilExit()
                if p.terminationStatus == 0 { return }   // launchd is replacing us
            }
        }
        let bundle = Bundle.main.bundleURL
        let isBundle = bundle.pathExtension == "app"
        let target = isBundle ? bundle.path : (Bundle.main.executableURL?.path ?? bundle.path)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", isBundle ? "sleep 0.7; exec /usr/bin/open -n \"$0\"" : "sleep 0.7; exec \"$0\"", target]
        try? p.run()
        NSApp.terminate(nil)
    }

    static var isDarkMode: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
    static func toggleDarkMode() {
        runAppleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
    }

    /// Locks the screen (display sleep locks when "require password immediately" is on).
    static func lockScreen() {
        run("/usr/bin/pmset", ["displaysleepnow"])
    }
    static func sleepMac() {
        run("/usr/bin/pmset", ["sleepnow"])
    }
    static func emptyTrash() {
        runAppleScript("tell application \"Finder\" to empty trash")
    }

    // Wi-Fi
    static var wifiDevice: String? {
        let out = run("/usr/sbin/networksetup", ["-listallhardwareports"])
        var found = false
        for line in out.components(separatedBy: "\n") {
            if line.contains("Wi-Fi") || line.contains("AirPort") { found = true; continue }
            if found, line.hasPrefix("Device:") {
                return line.replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
    static func wifiIsOn() -> Bool? {
        guard let dev = wifiDevice else { return nil }
        let out = run("/usr/sbin/networksetup", ["-getairportpower", dev])
        if out.contains("On") { return true }
        if out.contains("Off") { return false }
        return nil
    }
    static func setWifi(_ on: Bool) {
        guard let dev = wifiDevice else { return }
        run("/usr/sbin/networksetup", ["-setairportpower", dev, on ? "on" : "off"])
    }
}

/// Keep-awake ("caffeine") via a power-management assertion.
final class Caffeine: ObservableObject {
    static let shared = Caffeine()
    @Published private(set) var isOn = false
    private var assertion: IOPMAssertionID = 0

    func toggle() { set(!isOn) }

    func set(_ on: Bool) {
        if on, !isOn {
            var id: IOPMAssertionID = 0
            let ok = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "NotchIsland keep awake" as CFString, &id)
            if ok == kIOReturnSuccess { assertion = id; isOn = true }
        } else if !on, isOn {
            IOPMAssertionRelease(assertion)
            assertion = 0
            isOn = false
        }
    }
}

// MARK: - Calculator

/// A small, safe arithmetic evaluator (+ − × ÷ ^ % and parentheses). No NSExpression, so a
/// malformed query can never throw an Objective-C exception at us.
enum Calculator {
    static func looksLikeMath(_ s: String) -> Bool {
        let t = s.replacingOccurrences(of: " ", with: "")
        guard t.rangeOfCharacter(from: .decimalDigits) != nil,
              t.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/^%×÷")) != nil,
              t.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789.+-*/^%()×÷ ").inverted) == nil
        else { return false }
        return true
    }

    static func evaluate(_ s: String) -> Double? {
        var p = Parser(s.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: " ", with: ""))
        guard let v = p.expression(), p.atEnd, v.isFinite else { return nil }
        return v
    }

    static func format(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
        let f = NumberFormatter()
        f.maximumFractionDigits = 8
        f.minimumFractionDigits = 0
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    private struct Parser {
        let chars: [Character]
        var i = 0
        init(_ s: String) { chars = Array(s) }
        var atEnd: Bool { i >= chars.count }
        var peek: Character? { i < chars.count ? chars[i] : nil }

        mutating func expression() -> Double? {
            guard var v = term() else { return nil }
            while let c = peek, c == "+" || c == "-" {
                i += 1
                guard let r = term() else { return nil }
                v = c == "+" ? v + r : v - r
            }
            return v
        }
        mutating func term() -> Double? {
            guard var v = power() else { return nil }
            while let c = peek, c == "*" || c == "/" || c == "%" {
                i += 1
                guard let r = power() else { return nil }
                switch c {
                case "*": v *= r
                case "/": v /= r
                default: v = v.truncatingRemainder(dividingBy: r)
                }
            }
            return v
        }
        mutating func power() -> Double? {
            guard let base = unary() else { return nil }
            if peek == "^" {
                i += 1
                guard let e = power() else { return nil }
                return pow(base, e)
            }
            return base
        }
        mutating func unary() -> Double? {
            if peek == "-" { i += 1; return unary().map { -$0 } }
            if peek == "+" { i += 1; return unary() }
            return primary()
        }
        mutating func primary() -> Double? {
            if peek == "(" {
                i += 1
                guard let v = expression(), peek == ")" else { return nil }
                i += 1
                return v
            }
            var text = ""
            while let c = peek, c.isNumber || c == "." { text.append(c); i += 1 }
            return Double(text)
        }
    }
}

// MARK: - Unit conversion

enum UnitConverter {
    struct Result { let value: Double; let fromSymbol: String; let toSymbol: String }

    private static let table: [String: Dimension] = [
        "mm": UnitLength.millimeters, "cm": UnitLength.centimeters, "m": UnitLength.meters,
        "km": UnitLength.kilometers, "in": UnitLength.inches, "inch": UnitLength.inches, "inches": UnitLength.inches,
        "ft": UnitLength.feet, "feet": UnitLength.feet, "foot": UnitLength.feet, "yd": UnitLength.yards,
        "mi": UnitLength.miles, "mile": UnitLength.miles, "miles": UnitLength.miles,
        "g": UnitMass.grams, "kg": UnitMass.kilograms, "lb": UnitMass.pounds, "lbs": UnitMass.pounds,
        "oz": UnitMass.ounces, "st": UnitMass.stones,
        "c": UnitTemperature.celsius, "°c": UnitTemperature.celsius, "f": UnitTemperature.fahrenheit,
        "°f": UnitTemperature.fahrenheit, "k": UnitTemperature.kelvin,
        "ml": UnitVolume.milliliters, "l": UnitVolume.liters, "gal": UnitVolume.gallons,
        "cup": UnitVolume.cups, "cups": UnitVolume.cups, "floz": UnitVolume.fluidOunces,
        "kmh": UnitSpeed.kilometersPerHour, "km/h": UnitSpeed.kilometersPerHour, "kph": UnitSpeed.kilometersPerHour,
        "mph": UnitSpeed.milesPerHour, "ms": UnitSpeed.metersPerSecond, "m/s": UnitSpeed.metersPerSecond,
        "kb": UnitInformationStorage.kilobytes, "mb": UnitInformationStorage.megabytes,
        "gb": UnitInformationStorage.gigabytes, "tb": UnitInformationStorage.terabytes,
    ]

    private static let pattern = try! NSRegularExpression(
        pattern: #"^\s*(-?\d+(?:\.\d+)?)\s*([a-zA-Z°/]+)\s+(?:to|in|->|as)\s+([a-zA-Z°/]+)\s*$"#,
        options: [.caseInsensitive])

    static func convert(_ query: String) -> Result? {
        let ns = query as NSString
        guard let m = pattern.firstMatch(in: query, range: NSRange(location: 0, length: ns.length)) else { return nil }
        guard let value = Double(ns.substring(with: m.range(at: 1))) else { return nil }
        let fromKey = ns.substring(with: m.range(at: 2)).lowercased()
        let toKey = ns.substring(with: m.range(at: 3)).lowercased()
        guard let from = table[fromKey], let to = table[toKey],
              type(of: from) == type(of: to) else { return nil }
        let converted = Measurement(value: value, unit: from).converted(to: to).value
        return Result(value: converted, fromSymbol: from.symbol, toSymbol: to.symbol)
    }
}

// MARK: - Hints and privacy panes

/// A problem the island shows in its footer, optionally with the System Settings pane that fixes it.
struct IslandHint: Equatable {
    let text: String
    var settingsPane: String? = nil
}

/// Deep links into System Settings ▸ Privacy & Security.
enum PrivacyPane {
    static let accessibility = "com.apple.preference.security?Privacy_Accessibility"
    static let calendars = "com.apple.preference.security?Privacy_Calendars"
    static let fullDiskAccess = "com.apple.preference.security?Privacy_AllFiles"

    static func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:\(pane)") { NSWorkspace.shared.open(url) }
    }
}
