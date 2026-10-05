//
//  Premium3DIcon.swift
//  boringNotch / LiquidDynamo
//
//  Flagship 3D Vector Icon System
//  Provides offline, high-DPI, multi-layer 3D icons with realistic lighting,
//  specular highlights, drop shadows, and zero external search dependencies.
//

import AppKit
import Defaults
import SwiftUI

// MARK: - Premium 3D Icon Catalog

public enum Premium3DIcon: String, CaseIterable, Identifiable, Hashable {
    // 1. Context-Aware Icons
    case music
    case playlist
    case search
    case downloads
    case settings
    case userProfile
    case notifications
    case favorites
    case library
    case radio
    case equalizer
    case lyrics
    case albums
    case artists
    case cloudSync

    // 2. Device-Specific 3D Icons
    case airPods
    case headphones
    case androidPhone
    case battery
    case charging
    case wifi
    case cellular
    case carMode
    case desktopMac
    case smartSpeaker

    // 3. System & Playback Icons
    case cpu
    case stats
    case shelf
    case calendar
    case camera
    case volume
    case brightness
    case keyboard
    case mic
    case bluetooth
    case shuffle
    case repeatMode
    case previous
    case next
    case play
    case pause
    case generic

    public var id: String { rawValue }

    /// Primary SF symbol glyph base used for vector geometry
    public var baseSymbolName: String {
        switch self {
        case .music: return "music.note"
        case .playlist: return "music.note.list"
        case .search: return "magnifyingglass"
        case .downloads: return "arrow.down.circle.fill"
        case .settings: return "gearshape.fill"
        case .userProfile: return "person.crop.circle.fill"
        case .notifications: return "bell.fill"
        case .favorites: return "heart.fill"
        case .library: return "books.vertical.fill"
        case .radio: return "radio.fill"
        case .equalizer: return "slider.vertical.3"
        case .lyrics: return "quote.bubble.fill"
        case .albums: return "opticaldisc.fill"
        case .artists: return "mic.fill"
        case .cloudSync: return "arrow.triangle.2.circlepath.icloud.fill"
        case .airPods: return "airpodspro"
        case .headphones: return "headphones"
        case .androidPhone: return "iphone.gen3"
        case .battery: return "battery.75percent"
        case .charging: return "battery.100.bolt"
        case .wifi: return "wifi"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .carMode: return "car.fill"
        case .desktopMac: return "display"
        case .smartSpeaker: return "hifispeaker.fill"
        case .cpu: return "cpu.fill"
        case .stats: return "chart.bar.xaxis"
        case .shelf: return "tray.fill"
        case .calendar: return "calendar"
        case .camera: return "web.camera.fill"
        case .volume: return "speaker.wave.3.fill"
        case .brightness: return "sun.max.fill"
        case .keyboard: return "light.max"
        case .mic: return "mic.fill"
        case .bluetooth: return "antenna.radiowaves.left.and.right"
        case .shuffle: return "shuffle"
        case .repeatMode: return "repeat"
        case .previous: return "backward.fill"
        case .next: return "forward.fill"
        case .play: return "play.fill"
        case .pause: return "pause.fill"
        case .generic: return "sparkles"
        }
    }

    /// Curated gradient color palette for 3D body depth
    public var gradientPalette: [Color] {
        switch self {
        case .music, .albums:
            return [Color(red: 1.0, green: 0.28, blue: 0.45), Color(red: 0.85, green: 0.12, blue: 0.35), Color(red: 0.55, green: 0.05, blue: 0.25)]
        case .playlist, .library, .shelf:
            return [Color(red: 0.35, green: 0.55, blue: 0.98), Color(red: 0.22, green: 0.42, blue: 0.88), Color(red: 0.12, green: 0.25, blue: 0.65)]
        case .search, .cloudSync:
            return [Color(red: 0.30, green: 0.75, blue: 0.98), Color(red: 0.15, green: 0.55, blue: 0.88), Color(red: 0.08, green: 0.35, blue: 0.65)]
        case .downloads:
            return [Color(red: 0.25, green: 0.85, blue: 0.65), Color(red: 0.15, green: 0.70, blue: 0.50), Color(red: 0.08, green: 0.48, blue: 0.35)]
        case .settings, .cpu:
            return [Color(red: 0.85, green: 0.88, blue: 0.92), Color(red: 0.65, green: 0.68, blue: 0.74), Color(red: 0.45, green: 0.48, blue: 0.55)]
        case .userProfile:
            return [Color(red: 0.60, green: 0.40, blue: 0.95), Color(red: 0.45, green: 0.25, blue: 0.85), Color(red: 0.30, green: 0.15, blue: 0.65)]
        case .notifications:
            return [Color(red: 1.0, green: 0.82, blue: 0.25), Color(red: 0.95, green: 0.68, blue: 0.12), Color(red: 0.75, green: 0.48, blue: 0.08)]
        case .favorites:
            return [Color(red: 1.0, green: 0.25, blue: 0.35), Color(red: 0.88, green: 0.10, blue: 0.22), Color(red: 0.60, green: 0.05, blue: 0.15)]
        case .radio, .artists:
            return [Color(red: 0.95, green: 0.50, blue: 0.20), Color(red: 0.85, green: 0.38, blue: 0.12), Color(red: 0.60, green: 0.22, blue: 0.05)]
        case .equalizer:
            return [Color(red: 0.40, green: 0.75, blue: 0.98), Color(red: 0.70, green: 0.35, blue: 0.95), Color(red: 0.95, green: 0.25, blue: 0.55)]
        case .lyrics:
            return [Color(red: 0.85, green: 0.75, blue: 0.98), Color(red: 0.65, green: 0.55, blue: 0.85), Color(red: 0.45, green: 0.35, blue: 0.65)]
        case .airPods, .headphones, .smartSpeaker:
            return [Color(white: 0.98), Color(white: 0.82), Color(white: 0.58)]
        case .androidPhone, .desktopMac:
            return [Color(red: 0.45, green: 0.78, blue: 0.65), Color(red: 0.25, green: 0.60, blue: 0.48), Color(red: 0.15, green: 0.42, blue: 0.32)]
        case .battery, .charging:
            return [Color(red: 0.32, green: 0.88, blue: 0.45), Color(red: 0.20, green: 0.72, blue: 0.32), Color(red: 0.12, green: 0.50, blue: 0.20)]
        case .wifi, .cellular:
            return [Color(red: 0.35, green: 0.70, blue: 1.0), Color(red: 0.18, green: 0.50, blue: 0.92), Color(red: 0.10, green: 0.32, blue: 0.70)]
        case .carMode:
            return [Color(red: 0.95, green: 0.35, blue: 0.30), Color(red: 0.80, green: 0.20, blue: 0.18), Color(red: 0.55, green: 0.10, blue: 0.10)]
        case .stats:
            return [Color(red: 0.45, green: 0.85, blue: 0.95), Color(red: 0.25, green: 0.65, blue: 0.85), Color(red: 0.15, green: 0.45, blue: 0.65)]
        case .calendar:
            return [Color(red: 0.98, green: 0.40, blue: 0.35), Color(red: 0.85, green: 0.25, blue: 0.22), Color(red: 0.60, green: 0.15, blue: 0.15)]
        case .camera:
            return [Color(red: 0.65, green: 0.70, blue: 0.78), Color(red: 0.45, green: 0.50, blue: 0.58), Color(red: 0.25, green: 0.30, blue: 0.38)]
        case .volume:
            return [Color(red: 0.35, green: 0.65, blue: 0.98), Color(red: 0.20, green: 0.48, blue: 0.85), Color(red: 0.10, green: 0.30, blue: 0.65)]
        case .brightness:
            return [Color(red: 1.0, green: 0.85, blue: 0.30), Color(red: 0.98, green: 0.68, blue: 0.15), Color(red: 0.85, green: 0.45, blue: 0.08)]
        case .keyboard, .mic:
            return [Color(red: 0.75, green: 0.80, blue: 0.88), Color(red: 0.55, green: 0.60, blue: 0.68), Color(red: 0.35, green: 0.40, blue: 0.48)]
        case .bluetooth:
            return [Color(red: 0.25, green: 0.55, blue: 0.98), Color(red: 0.12, green: 0.38, blue: 0.85), Color(red: 0.08, green: 0.22, blue: 0.65)]
        case .shuffle, .repeatMode, .previous, .next, .play, .pause:
            return [Color(white: 0.98), Color(white: 0.85), Color(white: 0.65)]
        case .generic:
            return [Color(red: 0.75, green: 0.55, blue: 0.98), Color(red: 0.55, green: 0.35, blue: 0.85), Color(red: 0.35, green: 0.20, blue: 0.65)]
        }
    }

    /// Intelligent keyword/symbol resolver mapping any arbitrary name or SF Symbol to the closest 3D icon
    public static func from(name: String) -> Premium3DIcon {
        let lower = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Exact matches
        if let exact = Premium3DIcon(rawValue: lower) {
            return exact
        }

        // 2. Music & Audio
        if lower.contains("music") || lower.contains("song") || lower.contains("audio") || lower.contains("waveform") {
            return .music
        }
        if lower.contains("playlist") || lower.contains("list.bullet") || lower.contains("queue") {
            return .playlist
        }
        if lower.contains("lyric") || lower.contains("quote") || lower.contains("text.align") {
            return .lyrics
        }
        if lower.contains("album") || lower.contains("disc") || lower.contains("vinyl") {
            return .albums
        }
        if lower.contains("artist") || lower.contains("singer") {
            return .artists
        }
        if lower.contains("radio") {
            return .radio
        }
        if lower.contains("equalizer") || lower.contains("slider") || lower.contains("fader") {
            return .equalizer
        }

        // 3. Playback Controls
        if lower.contains("shuffle") { return .shuffle }
        if lower.contains("repeat") { return .repeatMode }
        if lower.contains("backward") || lower.contains("previous") { return .previous }
        if lower.contains("forward") || lower.contains("next") { return .next }
        if lower.contains("pause") { return .pause }
        if lower.contains("play") { return .play }

        // 4. Favorites & Notifications
        if lower.contains("heart") || lower.contains("favorite") || lower.contains("like") {
            return .favorites
        }
        if lower.contains("bell") || lower.contains("notification") || lower.contains("alert") {
            return .notifications
        }

        // 5. System Utilities
        if lower.contains("search") || lower.contains("magnifying") || lower.contains("find") {
            return .search
        }
        if lower.contains("download") || lower.contains("arrow.down") {
            return .downloads
        }
        if lower.contains("gear") || lower.contains("setting") || lower.contains("preference") {
            return .settings
        }
        if lower.contains("person") || lower.contains("user") || lower.contains("profile") || lower.contains("account") {
            return .userProfile
        }
        if lower.contains("book") || lower.contains("library") || lower.contains("catalog") {
            return .library
        }
        if lower.contains("tray") || lower.contains("shelf") {
            return .shelf
        }
        if lower.contains("calendar") || lower.contains("date") || lower.contains("event") {
            return .calendar
        }
        if lower.contains("cloud") || lower.contains("sync") || lower.contains("icloud") {
            return .cloudSync
        }
        if lower.contains("cpu") || lower.contains("chip") || lower.contains("processor") {
            return .cpu
        }
        if lower.contains("chart") || lower.contains("stat") || lower.contains("graph") || lower.contains("metric") {
            return .stats
        }

        // 6. Devices
        if lower.contains("airpod") {
            return .airPods
        }
        if lower.contains("headphone") || lower.contains("headset") || lower.contains("earphone") || lower.contains("beats") || lower.contains("sony") {
            return .headphones
        }
        if lower.contains("android") || lower.contains("pixel") || lower.contains("galaxy") || lower.contains("phone") || lower.contains("iphone") {
            return .androidPhone
        }
        if lower.contains("bolt") || lower.contains("charging") {
            return .charging
        }
        if lower.contains("battery") {
            return .battery
        }
        if lower.contains("wifi") || lower.contains("wi-fi") || lower.contains("wlan") {
            return .wifi
        }
        if lower.contains("cellular") || lower.contains("antenna") || lower.contains("mobile") || lower.contains("signal") {
            return .cellular
        }
        if lower.contains("car") || lower.contains("auto") || lower.contains("drive") {
            return .carMode
        }
        if lower.contains("display") || lower.contains("mac") || lower.contains("computer") || lower.contains("screen") || lower.contains("monitor") {
            return .desktopMac
        }
        if lower.contains("speaker") || lower.contains("homepod") || lower.contains("soundbar") {
            return .smartSpeaker
        }
        if lower.contains("bluetooth") {
            return .bluetooth
        }
        if lower.contains("camera") || lower.contains("webcam") || lower.contains("mirror") {
            return .camera
        }
        if lower.contains("volume") || lower.contains("sound") {
            return .volume
        }
        if lower.contains("sun") || lower.contains("brightness") || lower.contains("light") {
            return .brightness
        }
        if lower.contains("keyboard") || lower.contains("backlight") {
            return .keyboard
        }
        if lower.contains("mic") {
            return .mic
        }

        // 7. Guaranteed semantic fallback — NEVER a broken icon
        return .generic
    }
}

// MARK: - Premium 3D Icon View Engine

public struct Premium3DIconView: View {
    public let icon: Premium3DIcon
    public var size: CGFloat = 24
    public var isSelected: Bool = false
    public var customTint: Color? = nil
    public var interactive: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered: Bool = false
    @State private var pulseScale: CGFloat = 1.0

    public init(
        _ icon: Premium3DIcon,
        size: CGFloat = 24,
        isSelected: Bool = false,
        customTint: Color? = nil,
        interactive: Bool = true
    ) {
        self.icon = icon
        self.size = size
        self.isSelected = isSelected
        self.customTint = customTint
        self.interactive = interactive
    }

    public init(
        name: String,
        size: CGFloat = 24,
        isSelected: Bool = false,
        customTint: Color? = nil,
        interactive: Bool = true
    ) {
        self.icon = Premium3DIcon.from(name: name)
        self.size = size
        self.isSelected = isSelected
        self.customTint = customTint
        self.interactive = interactive
    }

    public var body: some View {
        ZStack {
            // 1. Ambient Glow underneath
            if isSelected || isHovered {
                Image(systemName: icon.baseSymbolName)
                    .font(.system(size: size * 0.92, weight: .bold))
                    .foregroundStyle((customTint ?? icon.gradientPalette.first ?? .white).opacity(isSelected ? 0.6 : 0.35))
                    .blur(radius: size * 0.22)
            }

            // 2. Directional Drop Shadow for 3D Elevation
            Image(systemName: icon.baseSymbolName)
                .font(.system(size: size * 0.92, weight: .bold))
                .foregroundStyle(Color.black.opacity(isSelected ? 0.75 : 0.45))
                .offset(x: 0, y: isHovered ? size * 0.14 : size * 0.09)
                .blur(radius: isHovered ? size * 0.16 : size * 0.10)

            // 3. Extruded Body Depth Layer (Darker gradient base)
            Image(systemName: icon.baseSymbolName)
                .font(.system(size: size * 0.92, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: bodyGradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .offset(y: size * 0.03)

            // 4. Primary Chiseled Face with Specular Lighting
            Image(systemName: icon.baseSymbolName)
                .font(.system(size: size * 0.92, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: faceGradientColors,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // 5. Specular Rim Highlight on Top Edge
            Image(systemName: icon.baseSymbolName)
                .font(.system(size: size * 0.92, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(isSelected ? 0.95 : 0.75), location: 0.0),
                            .init(color: Color.white.opacity(isSelected ? 0.35 : 0.15), location: 0.35),
                            .init(color: Color.clear, location: 0.70)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.screen)
                .offset(y: -size * 0.03)
                .mask(
                    Image(systemName: icon.baseSymbolName)
                        .font(.system(size: size * 0.92, weight: .bold))
                )

            // 6. Recessed Cavity Shadow for Beveled Creases
            Image(systemName: icon.baseSymbolName)
                .font(.system(size: size * 0.92, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: Color.clear, location: 0.45),
                            .init(color: Color.black.opacity(0.40), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.multiply)
                .offset(y: size * 0.03)
                .mask(
                    Image(systemName: icon.baseSymbolName)
                        .font(.system(size: size * 0.92, weight: .bold))
                )
        }
        .frame(width: size, height: size)
        .scaleEffect(pulseScale * (isHovered && interactive ? 1.08 : 1.0))
        .offset(y: (isHovered && interactive) ? -size * 0.06 : (isSelected ? -size * 0.04 : 0))
        .rotation3DEffect(
            .degrees(reduceMotion || !interactive ? 0 : (isHovered ? 6 : 0)),
            axis: (x: 1.0, y: -0.5, z: 0.0),
            perspective: 0.5
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.65), value: isHovered)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isSelected)
        .onHover { hovering in
            guard interactive else { return }
            isHovered = hovering
        }
    }

    private var faceGradientColors: [Color] {
        if let customTint = customTint {
            return [customTint.opacity(1.0), customTint.opacity(0.85), customTint.opacity(0.65)]
        }
        return icon.gradientPalette
    }

    private var bodyGradientColors: [Color] {
        if let customTint = customTint {
            return [customTint.opacity(0.6), customTint.opacity(0.4), Color.black.opacity(0.8)]
        }
        let palette = icon.gradientPalette
        if palette.count >= 3 {
            return [palette[1].opacity(0.7), palette[2], Color.black.opacity(0.75)]
        }
        return [Color.black.opacity(0.8), Color.black]
    }
}
