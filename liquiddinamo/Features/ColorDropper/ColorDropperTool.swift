//
//  ColorDropperTool.swift
//  LiquidDynamo
//
//  High precision screen color sampler using NSColorSampler.
//  Provides HEX, RGB, HSL swatches, instant copy, and recent color history.
//

import AppKit
import Foundation
import SwiftUI

public struct PickedColorRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let hex: String
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        hex: String,
        red: Double,
        green: Double,
        blue: Double,
        alpha: Double = 1.0,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.hex = hex
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
        self.timestamp = timestamp
    }

    public var rgbString: String {
        let r = Int(round(red * 255))
        let g = Int(round(green * 255))
        let b = Int(round(blue * 255))
        return "rgb(\(r), \(g), \(b))"
    }

    public var hslString: String {
        let r = red
        let g = green
        let b = blue
        let maxVal = max(r, g, b)
        let minVal = min(r, g, b)
        let delta = maxVal - minVal

        var h: Double = 0
        var s: Double = 0
        let l: Double = (maxVal + minVal) / 2.0

        if delta > 0.00001 {
            s = l > 0.5 ? delta / (2.0 - maxVal - minVal) : delta / (maxVal + minVal)
            if maxVal == r {
                h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxVal == g {
                h = ((b - r) / delta) + 2.0
            } else {
                h = ((r - g) / delta) + 4.0
            }
            h *= 60.0
            if h < 0 { h += 360.0 }
        }

        let hInt = Int(round(h))
        let sInt = Int(round(s * 100))
        let lInt = Int(round(l * 100))
        return "hsl(\(hInt), \(sInt)%, \(lInt)%)"
    }

    public var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    public var isLight: Bool {
        // Relative luminance per ITU-R BT.709
        let lum = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return lum > 0.55
    }
}

@MainActor
public final class ColorDropperTool: ObservableObject {
    public static let shared = ColorDropperTool()

    @Published public private(set) var currentColor: PickedColorRecord?
    @Published public private(set) var recentColors: [PickedColorRecord] = []
    @Published public private(set) var isSampling: Bool = false
    @Published public var copiedFormatFeedback: String? = nil

    private var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("LiquidDynamo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("recent_colors.json")
    }

    private init() {
        loadRecentColors()
    }

    // MARK: - Screen Sampling Pipeline

    public func sampleColor() {
        guard !isSampling else { return }
        isSampling = true

        // Ensure the island is held open while the system magnifier is on screen
        IslandController.shared.isPinnedOpen = true

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            defer {
                self.isSampling = false
            }

            let sampler = NSColorSampler()
            guard let sampledColor = await sampler.sample() else {
                // User cancelled color sampling (hit Escape)
                return
            }

            // Convert sampled color to calibrated sRGB color space
            guard let srgbColor = sampledColor.usingColorSpace(.sRGB) else {
                return
            }

            let r = Double(srgbColor.redComponent)
            let g = Double(srgbColor.greenComponent)
            let b = Double(srgbColor.blueComponent)
            let a = Double(srgbColor.alphaComponent)

            let rInt = Int(round(r * 255))
            let gInt = Int(round(g * 255))
            let bInt = Int(round(b * 255))
            let hex = String(format: "#%02X%02X%02X", rInt, gInt, bInt)

            let record = PickedColorRecord(
                hex: hex,
                red: r,
                green: g,
                blue: b,
                alpha: a
            )

            self.currentColor = record
            self.addToRecent(record)

            // Pin and open the color dropper detail card without collapsing
            IslandController.shared.isPinnedOpen = true
            IslandController.shared.activeOrganicItem = .colorDropper
            if IslandController.shared.state != .expanded {
                IslandController.shared.transitionTo(.expanded)
            }

            // Automatically copy HEX code for convenience
            self.copyFormat(record.hex, formatName: "HEX")
        }
    }

    // MARK: - Clipboard Actions

    public func copyFormat(_ string: String, formatName: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)

        copiedFormatFeedback = formatName
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if self?.copiedFormatFeedback == formatName {
                self?.copiedFormatFeedback = nil
            }
        }
    }

    public func selectRecent(_ record: PickedColorRecord) {
        self.currentColor = record
    }

    public func clearRecent() {
        recentColors.removeAll()
        saveRecentColors()
    }

    // MARK: - Storage

    private func addToRecent(_ record: PickedColorRecord) {
        recentColors.removeAll { $0.hex.uppercased() == record.hex.uppercased() }
        recentColors.insert(record, at: 0)
        if recentColors.count > 16 {
            recentColors.removeLast(recentColors.count - 16)
        }
        saveRecentColors()
    }

    private func saveRecentColors() {
        do {
            let data = try JSONEncoder().encode(recentColors)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("Failed to save recent colors: \(error)")
        }
    }

    private func loadRecentColors() {
        guard let data = try? Data(contentsOf: storageURL),
              let list = try? JSONDecoder().decode([PickedColorRecord].self, from: data) else {
            // Seed with classic Apple default accent if empty
            let defaultColor = PickedColorRecord(hex: "#007AFF", red: 0.0, green: 0.478, blue: 1.0)
            self.currentColor = defaultColor
            self.recentColors = [defaultColor]
            return
        }
        self.recentColors = list
        self.currentColor = list.first
    }
}
