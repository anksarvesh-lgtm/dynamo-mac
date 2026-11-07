import AppKit
import IslandCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Environment

private struct AirPodsRevealedKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    /// False while the Island is still opening; the artwork waits for it (set by the root view).
    var airPodsRevealed: Bool {
        get { self[AirPodsRevealedKey.self] }
        set { self[AirPodsRevealedKey.self] = newValue }
    }
}

// MARK: - Artwork source

/// Resolves the best available product artwork for an AirPods model, in order:
/// 1. a bundled, licensed, transparent render — `Island.app/Contents/Resources/AirPods/<model>.png`;
/// 2. the model-specific device artwork macOS itself provides for that product (public `UTType` +
///    `NSWorkspace.icon(for:)` — nothing of Apple's is redistributed);
/// 3. nil — the card then shows no picture rather than a fake one.
@MainActor
enum AirPodsArtwork {
    private static var cache: [String: NSImage] = [:]

    /// System device types per model, used when the product ID is unknown.
    private static let typeIdentifiers: [AirPodsModel: [String]] = [
        .airPodsPro2USBC: ["com.apple.airpods-pro-gen2-2023", "com.apple.airpods-pro-gen2"],
        .airPodsPro2: ["com.apple.airpods-pro-gen2"],
        .airPodsPro3: ["com.apple.airpods-pro-2025", "com.apple.airpods-pro-gen2-2023"],
        .airPodsPro: ["com.apple.airpods-pro", "com.apple.airpods-pro-gen2"],
        .airPodsMax: ["com.apple.airpods-max", "com.apple.airpods-max-2024"],
        .airPodsMaxUSBC: ["com.apple.airpods-max-2024", "com.apple.airpods-max"],
        .airPods4: ["com.apple.airpods-gen4"],
        .airPods4ANC: ["com.apple.airpods-gen4"],
        .airPods3: ["com.apple.airpods-gen3"],
        .airPods2: ["com.apple.airpods-gen2", "com.apple.airpods"],
        .airPods1: ["com.apple.airpods"],
        .unknownAirPods: ["com.apple.airpods-gen4", "com.apple.airpods"],
    ]

    /// True when the image is a bundled transparent render (drawn larger, no tile).
    static func isBundledRender(model: AirPodsModel) -> Bool { bundled(model) != nil }

    static func image(model: AirPodsModel, productID: Int?) -> NSImage? {
        let key = "\(model.rawValue)-\(productID ?? -1)"
        if let cached = cache[key] { return cached }
        let img = bundled(model) ?? systemArtwork(model: model, productID: productID)
        if let img { cache[key] = img }
        return img
    }

    private static func bundled(_ model: AirPodsModel) -> NSImage? {
        for name in model.artworkNames {
            for ext in ["png", "heic", "tiff"] {
                if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "AirPods"),
                   let img = NSImage(contentsOf: url) { return img }
            }
        }
        return nil
    }

    private static func systemArtwork(model: AirPodsModel, productID: Int?) -> NSImage? {
        var types: [UTType] = []
        if let pid = productID,
           let t = UTType(tag: AirPodsModel.deviceModelCode(productID: pid), tagClass: UTTagClass(rawValue: "com.apple.device-model-code"), conformingTo: nil),
           t.isDeclared {
            types.append(t)
        }
        types += (typeIdentifiers[model] ?? []).compactMap { UTType($0) }.filter(\.isDeclared)
        guard let type = types.first else { return nil }
        let icon = NSWorkspace.shared.icon(for: type)
        icon.size = NSSize(width: 256, height: 256)
        return icon
    }
}

// MARK: - Artwork view

/// The product picture and its entrance:
/// scale 0.65 → 1.03 → 1.0 · opacity 0 → 1 · blur 5 → 0 · a slight rise. Responsive spring, no spin,
/// no glow. Waits until the Island has opened (`airPodsRevealed`).
struct AirPodsArtworkView: View {
    let model: AirPodsModel
    let productID: Int?
    var size: CGFloat = 64
    var animatesEntrance = true
    @Environment(\.airPodsRevealed) private var revealed
    @Environment(\.islandReduceMotion) private var reduceMotion
    @Environment(\.islandNamespace) private var ns

    @State private var scale: CGFloat = 0.65
    @State private var opacity: Double = 0
    @State private var blur: CGFloat = 5
    @State private var lift: CGFloat = 6
    @State private var started = false

    var body: some View {
        Group {
            if let img = AirPodsArtwork.image(model: model, productID: productID) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(scale)
        .opacity(opacity)
        .blur(radius: blur)
        .offset(y: lift)
        .islandMatched("airpods-artwork", in: ns)
        .accessibilityHidden(true)
        .onAppear { if revealed { enter() } }
        .onChange(of: revealed) { _, now in if now { enter() } }
    }

    private func enter() {
        guard !started else { return }
        started = true
        guard animatesEntrance, !reduceMotion else {
            scale = 1; opacity = 1; blur = 0; lift = 0
            return
        }
        // Grow slightly past full size on a responsive spring…
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            scale = 1.03
            opacity = 1
            blur = 0
            lift = 0
        }
        // …then settle to exactly 1.0 without a bounce.
        withAnimation(.spring(response: 0.3, dampingFraction: 1).delay(0.24)) {
            scale = 1.0
        }
    }
}

// MARK: - Battery view

/// Battery as the system reports it. Earbuds: the lower bud as a thin ring with its percentage, with
/// left/right/case in the accessibility label and tooltip. Hidden when nothing is reported — never guessed.
struct AirPodsBatteryView: View {
    let battery: AirPodsBattery?
    var diameter: CGFloat = 34

    var body: some View {
        if let battery, let level = battery.headline {
            ZStack {
                Circle().stroke(.white.opacity(0.18), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(level) / 100)
                    .stroke(level <= 20 ? IslandPalette.batteryLow : IslandPalette.batteryGood,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(level)")
                    .font(.system(size: diameter * 0.32, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .frame(width: diameter, height: diameter)
            .help(detail(battery))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Battery")
            .accessibilityValue(detail(battery))
            .transition(.opacity)
        }
    }

    private func detail(_ b: AirPodsBattery) -> String {
        if let s = b.single { return "\(s)%" }
        return [b.left.map { "Left \($0)%" }, b.right.map { "Right \($0)%" }, b.caseLevel.map { "Case \($0)%" }]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

// MARK: - Connection card

/// Expanded card: artwork · name + status · battery — a short, wide layout so the Island expands
/// horizontally out of the notch rather than dropping down.
struct AirPodsConnectionView: View {
    let device: DeviceActivity
    let id: String
    @Environment(\.airPodsRevealed) private var revealed
    @Environment(\.islandReduceMotion) private var reduceMotion

    private var model: AirPodsModel { device.airPods ?? .unknownAirPods }

    var body: some View {
        HStack(spacing: 14) {
            AirPodsArtworkView(model: model, productID: device.productID, size: 60)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(device.connected ? "Connected" : "Disconnected")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(IslandPalette.secondaryText)
            }
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed || reduceMotion ? 0 : 3)
            .animation(.spring(response: 0.36, dampingFraction: 0.9).delay(revealed ? 0.12 : 0), value: revealed)
            Spacer(minLength: 0)
            AirPodsBatteryView(battery: device.battery)
                .opacity(revealed ? 1 : 0)
                .animation(.easeOut(duration: 0.25).delay(revealed ? 0.2 : 0), value: revealed)
                .animation(.easeOut(duration: 0.3), value: device.battery)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(device.name) \(device.connected ? "connected" : "disconnected")")
    }
}

// MARK: - Compact

struct DeviceCompactLeading: View {
    let device: DeviceActivity
    let id: String
    var body: some View {
        if let model = device.airPods {
            AirPodsArtworkView(model: model, productID: device.productID, size: 22, animatesEntrance: false)
        } else {
            SimpleCompactLeading(symbol: DevicePresentation.symbol(device), tint: .white, text: device.name, id: id)
        }
    }
}

/// Compact trailing: battery when known, otherwise a green check.
struct DeviceCompactTrailing: View {
    let device: DeviceActivity
    var body: some View {
        if device.connected, let level = device.battery?.headline {
            AirPodsBatteryView(battery: device.battery, diameter: 20)
                .accessibilityLabel("Battery \(level)%")
        } else {
            Image(systemName: device.connected ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(device.connected ? IslandPalette.batteryGood : .white.opacity(0.55))
                .accessibilityHidden(true)
        }
    }
}

/// Non-AirPods headphones keep the simple event card.
struct HeadphonesConnectedView: View {
    let device: DeviceActivity
    let id: String
    var body: some View {
        EventLikeExpanded(symbol: DevicePresentation.symbol(device), tint: .white, title: device.name,
                          subtitle: device.connected ? "Connected" : "Disconnected", id: id)
    }
}
