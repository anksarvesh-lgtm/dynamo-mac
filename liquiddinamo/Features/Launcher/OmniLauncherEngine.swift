//
//  OmniLauncherEngine.swift
//  LiquidDynamo
//
//  Unified Spotlight-style launcher combining:
//  - NotchIsland's math calculator & unit converter
//  - island's category-routed search (web, files, apps, AI research)
//  - Quick actions (timers, system controls)
//

import AppKit
import Combine
import Foundation

public struct OmniLauncherItem: Identifiable, Sendable {
    public enum Kind: Sendable {
        case app(URL)
        case calc(String)
        case convert(String)
        case file(URL)
        case aiResearch(String)
        case quickAction(String)
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let subtitle: String
    public let symbol: String

    public init(id: String, kind: Kind, title: String, subtitle: String, symbol: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
    }
}

@MainActor
public final class OmniLauncherEngine: ObservableObject {
    public static let shared = OmniLauncherEngine()

    @Published public var queryText: String = ""
    @Published public private(set) var results: [OmniLauncherItem] = []
    @Published public var isVisible: Bool = false

    private var cancellables = Set<AnyCancellable>()

    private init() {
        $queryText
            .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
            .sink { [weak self] q in
                self?.performSearch(q)
            }
            .store(in: &cancellables)
    }

    public func toggleVisibility() {
        isVisible.toggle()
        if isVisible {
            queryText = ""
            results = []
        }
    }

    private func performSearch(_ rawQuery: String) {
        let q = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            results = recentQuickActions()
            return
        }

        var out: [OmniLauncherItem] = []

        // 1. Math Calculator Evaluation
        if MathParser.looksLikeMath(q), let val = MathParser.evaluate(q) {
            let formatted = MathParser.format(val)
            out.append(
                OmniLauncherItem(
                    id: "calc_\(formatted)",
                    kind: .calc(formatted),
                    title: formatted,
                    subtitle: "= \(q)   ·   Return to copy",
                    symbol: "equal.circle.fill"
                )
            )
        }

        // 2. Unit Converter
        if let converted = OmniUnitConverter.convert(q) {
            let formatted = "\(MathParser.format(converted.value)) \(converted.toSymbol)"
            out.append(
                OmniLauncherItem(
                    id: "conv_\(formatted)",
                    kind: .convert(formatted),
                    title: formatted,
                    subtitle: "\(q)   ·   Return to copy",
                    symbol: "arrow.left.arrow.right.circle.fill"
                )
            )
        }

        // 3. AI Web Search Prefix (? or ask)
        let lower = q.lowercased()
        if lower.hasPrefix("?") || lower.hasPrefix("ask ") {
            let prompt = lower.hasPrefix("?") ? String(q.dropFirst()).trimmingCharacters(in: .whitespaces) : String(q.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            if !prompt.isEmpty {
                out.append(
                    OmniLauncherItem(
                        id: "ai_\(prompt)",
                        kind: .aiResearch(prompt),
                        title: "Ask AI & Web: \"\(prompt)\"",
                        subtitle: "Searches web citations and synthesizes instant answer",
                        symbol: "sparkles"
                    )
                )
            }
        }

        // 4. Timer Trigger (e.g. "timer 20 min")
        if let minutes = extractTimerMinutes(from: q) {
            out.append(
                OmniLauncherItem(
                    id: "timer_\(minutes)",
                    kind: .quickAction("timer"),
                    title: "Start \(minutes)-minute focus timer",
                    subtitle: "Runs timer countdown in Dynamic Island",
                    symbol: "timer"
                )
            )
        }

        // 5. Installed Applications Search
        let apps = searchInstalledApplications(query: q)
        out.append(contentsOf: apps.prefix(5))

        self.results = out
    }

    private func recentQuickActions() -> [OmniLauncherItem] {
        return [
            OmniLauncherItem(id: "qa_shelf", kind: .quickAction("shelf"), title: "Open Drop Shelf", subtitle: "Temporary storage and batch conversion", symbol: "tray.full.fill"),
            OmniLauncherItem(id: "qa_phone", kind: .quickAction("phone"), title: "MacLink Phone Deck", subtitle: "Telephony, screen mirror, and controls", symbol: "iphone.gen3"),
            OmniLauncherItem(id: "qa_clamshell", kind: .quickAction("clamshell"), title: "Keep Awake (Lid Closed)", subtitle: "Block sleep with clamshell shut", symbol: "bolt.shield.fill"),
            OmniLauncherItem(id: "qa_stats", kind: .quickAction("stats"), title: "System Power & Hardware Stats", subtitle: "Wattage, battery cycles, CPU telemetry", symbol: "gauge.with.needle.fill")
        ]
    }

    private func extractTimerMinutes(from query: String) -> Int? {
        let lower = query.lowercased()
        guard lower.contains("timer") else { return nil }
        let digits = lower.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        if let first = digits.first, let val = Int(first), val > 0, val <= 1440 {
            return val
        }
        return nil
    }

    private func searchInstalledApplications(query: String) -> [OmniLauncherItem] {
        let appDirs = ["/Applications", "/System/Applications", "\(NSHomeDirectory())/Applications"]
        var matches: [OmniLauncherItem] = []
        let lowerQ = query.lowercased()

        for dir in appDirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for item in contents where item.hasSuffix(".app") {
                let name = item.replacingOccurrences(of: ".app", with: "")
                if name.lowercased().contains(lowerQ) {
                    let fullPath = "\(dir)/\(item)"
                    matches.append(
                        OmniLauncherItem(
                            id: fullPath,
                            kind: .app(URL(fileURLWithPath: fullPath)),
                            title: name,
                            subtitle: fullPath,
                            symbol: "app.fill"
                        )
                    )
                }
            }
        }
        return matches
    }
}

// MARK: - Mathematical Expression Parser

public enum MathParser {
    public static func looksLikeMath(_ s: String) -> Bool {
        let t = s.replacingOccurrences(of: " ", with: "")
        guard t.rangeOfCharacter(from: .decimalDigits) != nil,
              t.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/^%×÷")) != nil,
              t.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789.+-*/^%()×÷ ").inverted) == nil else {
            return false
        }
        return true
    }

    public static func evaluate(_ s: String) -> Double? {
        let sanitized = s.replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: " ", with: "")
        var parser = Parser(sanitized)
        guard let result = parser.parseExpression(), parser.isAtEnd, result.isFinite else { return nil }
        return result
    }

    public static func format(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 6
        formatter.minimumFractionDigits = 0
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    private struct Parser {
        let chars: [Character]
        var index = 0
        init(_ s: String) { self.chars = Array(s) }
        var isAtEnd: Bool { index >= chars.count }

        mutating func parseExpression() -> Double? {
            guard var val = parseTerm() else { return nil }
            while !isAtEnd {
                let op = chars[index]
                if op == "+" {
                    index += 1
                    guard let right = parseTerm() else { return nil }
                    val += right
                } else if op == "-" {
                    index += 1
                    guard let right = parseTerm() else { return nil }
                    val -= right
                } else {
                    break
                }
            }
            return val
        }

        mutating func parseTerm() -> Double? {
            guard var val = parseFactor() else { return nil }
            while !isAtEnd {
                let op = chars[index]
                if op == "*" {
                    index += 1
                    guard let right = parseFactor() else { return nil }
                    val *= right
                } else if op == "/" {
                    index += 1
                    guard let right = parseFactor(), right != 0 else { return nil }
                    val /= right
                } else {
                    break
                }
            }
            return val
        }

        mutating func parseFactor() -> Double? {
            guard !isAtEnd else { return nil }
            if chars[index] == "(" {
                index += 1
                guard let val = parseExpression() else { return nil }
                if !isAtEnd && chars[index] == ")" { index += 1 }
                return val
            }
            if chars[index] == "-" {
                index += 1
                guard let val = parseFactor() else { return nil }
                return -val
            }
            var numStr = ""
            while !isAtEnd && (chars[index].isNumber || chars[index] == ".") {
                numStr.append(chars[index])
                index += 1
            }
            return Double(numStr)
        }
    }
}

// MARK: - Unit Converter

public enum OmniUnitConverter {
    public struct ConvertedResult {
        public let value: Double
        public let fromSymbol: String
        public let toSymbol: String
    }

    private static let table: [String: Dimension] = [
        "mm": UnitLength.millimeters, "cm": UnitLength.centimeters, "m": UnitLength.meters,
        "km": UnitLength.kilometers, "in": UnitLength.inches, "ft": UnitLength.feet,
        "mi": UnitLength.miles, "g": UnitMass.grams, "kg": UnitMass.kilograms,
        "lb": UnitMass.pounds, "oz": UnitMass.ounces,
        "c": UnitTemperature.celsius, "f": UnitTemperature.fahrenheit, "k": UnitTemperature.kelvin,
        "ml": UnitVolume.milliliters, "l": UnitVolume.liters, "gal": UnitVolume.gallons,
        "kmh": UnitSpeed.kilometersPerHour, "mph": UnitSpeed.milesPerHour,
        "mb": UnitInformationStorage.megabytes, "gb": UnitInformationStorage.gigabytes, "tb": UnitInformationStorage.terabytes
    ]

    private static let regex = try! NSRegularExpression(
        pattern: #"^\s*(-?\d+(?:\.\d+)?)\s*([a-zA-Z°/]+)\s+(?:to|in|->|as)\s+([a-zA-Z°/]+)\s*$"#,
        options: [.caseInsensitive]
    )

    public static func convert(_ query: String) -> ConvertedResult? {
        let ns = query as NSString
        guard let match = regex.firstMatch(in: query, range: NSRange(location: 0, length: ns.length)),
              let val = Double(ns.substring(with: match.range(at: 1))) else { return nil }
        let fromKey = ns.substring(with: match.range(at: 2)).lowercased()
        let toKey = ns.substring(with: match.range(at: 3)).lowercased()
        guard let fromUnit = table[fromKey], let toUnit = table[toKey],
              type(of: fromUnit) == type(of: toUnit) else { return nil }
        let convertedVal = Measurement(value: val, unit: fromUnit).converted(to: toUnit).value
        return ConvertedResult(value: convertedVal, fromSymbol: fromUnit.symbol, toSymbol: toUnit.symbol)
    }
}

