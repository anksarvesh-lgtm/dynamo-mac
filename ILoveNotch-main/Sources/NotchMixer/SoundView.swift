// SPDX-License-Identifier: MIT
import AppKit
import NotchFeatures
import SwiftUI

/// The Sound tab: the Mac's outputs and inputs on the left, to switch between, and faders on the
/// right: the output's volume, the microphone's, then one for each app playing sound, tinted from
/// its icon, with the icon under it. Drag a fader to set the volume; click the icon to mute. More
/// apps than fit scroll sideways.
public struct SoundView: View {
    let mixer: Mixer

    public init(mixer: Mixer) {
        self.mixer = mixer
    }

    public var body: some View {
        HStack(spacing: 0) {
            DeviceList(mixer: mixer)
                .frame(width: 118)
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(width: 1)
                .padding(.vertical, 2)
                .padding(.leading, 8)
            faders
        }
        .overlay(alignment: .top) {
            if mixer.needsPermission {
                permission.transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: mixer.needsPermission)
        .onAppear { mixer.appeared() }
        .onDisappear { mixer.disappeared() }
    }

    private var faders: some View {
        GeometryReader { proxy in
            // Names fit under the icons in a taller notch; the icons alone say who's who otherwise.
            // A short notch gets slimmer faders, so a third app peeks in to show the row scrolls.
            let names = proxy.size.height >= 150
            let slim = proxy.size.height < 120
            ScrollView(.horizontal) {
                HStack(alignment: .bottom, spacing: slim ? 6 : 8) {
                    if let output = mixer.output { deviceFader(output, .output, names: names, slim: slim) }
                    if let input = mixer.input { deviceFader(input, .input, names: names, slim: slim) }
                    Capsule()
                        .fill(.white.opacity(0.12))
                        .frame(width: 1)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 3)
                    if mixer.apps.isEmpty {
                        empty
                    } else {
                        ForEach(Array(mixer.apps.enumerated()), id: \.element.id) { index, app in
                            fader(app, names: names, slim: slim, order: index + 2)
                        }
                    }
                }
                .padding(.horizontal, slim ? 6 : 8)
                // Centered like a mixing desk while it fits; scrolls sideways once it doesn't.
                .frame(minWidth: proxy.size.width, maxHeight: .infinity, alignment: .bottom)
            }
            .scrollIndicators(.never)
            .fadingEdges(.horizontal, length: 8)
        }
    }

    /// The output's fader is white and the microphone's orange, the color of macOS's mic light.
    private func deviceFader(_ device: DeviceLevel, _ direction: SoundDirection, names: Bool, slim: Bool)
        -> some View
    {
        let output = direction == .output
        let symbol =
            device.isMuted
            ? (output ? "speaker.slash.fill" : "mic.slash.fill")
            : device.symbol ?? (output ? Self.speaker(device.level) : "mic.fill")
        return Fader(
            title: Self.shortName(device.name), level: device.level, muted: device.isMuted,
            tint: output ? .white : .orange, playing: false, enabled: device.hasVolume, names: names, slim: slim,
            order: output ? 0 : 1, badge: nil, set: { mixer.setDeviceLevel($0, for: direction) },
            toggleMute: { mixer.toggleDeviceMute(direction) }, reset: nil,
            icon: {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 6.5, style: .continuous))
            })
    }

    private func fader(_ app: MixerApp, names: Bool, slim: Bool, order: Int) -> some View {
        Fader(
            title: app.name, level: mixer.level(of: app.id), muted: mixer.isMuted(app.id), tint: mixer.tint(for: app),
            playing: app.isPlaying, enabled: true, names: names, slim: slim, order: order, badge: "speaker.slash.fill",
            set: { mixer.setLevel($0, of: app.id) }, toggleMute: { mixer.toggleMute(app.id) },
            reset: mixer.isAdjusted(app.id) ? { mixer.reset(app.id) } : nil,
            icon: {
                Image(nsImage: mixer.icon(for: app))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 26, height: 26)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            })
    }

    /// What fits under a fader or in the device list: "AirPods Pro" out of "Niyam's AirPods Pro",
    /// "Speakers" out of "MacBook Pro Speakers", "iPhone Microphone" out of "Niyam's iPhone
    /// Microphone".
    nonisolated static func shortName(_ name: String) -> String {
        if let airPods = name.range(of: "AirPods") { return String(name[airPods.lowerBound...]) }
        if name.hasSuffix("Headphones") { return "Headphones" }
        var name = name
        if let owner = name.range(of: "'s ") ?? name.range(of: "’s ") { name = String(name[owner.upperBound...]) }
        let macs = ["MacBook Pro ", "MacBook Air ", "MacBook ", "iMac ", "Mac mini ", "Mac Studio ", "Mac Pro "]
        if let mac = macs.first(where: { name.hasPrefix($0) }) { name = String(name.dropFirst(mac.count)) }
        return name
    }

    /// A speaker with as many waves as the level, like the volume in the closed notch.
    private static func speaker(_ level: Double) -> String {
        switch level {
        case ..<0.005: "speaker.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }

    private var empty: some View {
        VStack(spacing: 5) {
            Image(systemName: "waveform")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
            Text("Apps playing sound show up here")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(width: 92)
        .frame(maxHeight: .infinity)
    }

    private var permission: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text("Allow System Audio Recording to change app volumes").lineLimit(1)
            Button("Open Settings") { NSWorkspace.shared.open(.privacySettings("Privacy_AudioCapture")) }
                .buttonStyle(.plain)
                .fontWeight(.semibold)
        }
        .font(.caption2)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.black.opacity(0.8), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

/// The Mac's outputs, or its inputs, to switch between as in Control Center: the current one lit
/// and ticked, and the light slides to the one you pick. Bluetooth devices join while connected.
private struct DeviceList: View {
    let mixer: Mixer

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var direction = SoundDirection.output
    @Namespace private var selection

    var body: some View {
        let devices = direction == .output ? mixer.outputs : mixer.inputs
        let current = (direction == .output ? mixer.output : mixer.input)?.id
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                segment(.output, symbol: "speaker.wave.2.fill", title: "Output")
                segment(.input, symbol: "mic.fill", title: "Input")
            }
            .padding(2)
            .background(.white.opacity(0.07), in: Capsule())
            ScrollView(.vertical) {
                VStack(spacing: 2) {
                    ForEach(devices) { device in
                        DeviceRow(device: device, current: device.id == current, selection: selection) {
                            mixer.choose(device, for: direction)
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            .fadingEdges(.vertical, length: 6)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: current)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: devices)
    }

    private func segment(_ kind: SoundDirection, symbol: String, title: String) -> some View {
        let chosen = direction == kind
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) { direction = kind }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 8.5, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(chosen ? 1 : 0.5))
            .frame(maxWidth: .infinity)
            .frame(height: 18)
            .background {
                if chosen {
                    Capsule().fill(.white.opacity(0.16)).matchedGeometryEffect(id: "segment", in: selection)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(kind == .output ? "Where sound plays" : "Where sound comes in")
        .accessibilityLabel(kind == .output ? "Output devices" : "Input devices")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

private struct DeviceRow: View {
    let device: SoundDevice
    let current: Bool
    let selection: Namespace.ID
    let choose: () -> Void

    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        Button(action: choose) {
            HStack(spacing: 5) {
                Image(systemName: device.symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                    .frame(width: 15)
                Text(SoundView.shortName(device.name))
                    .font(.system(size: 11))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if current {
                    Image(systemName: "checkmark").font(.system(size: 8.5, weight: .bold))
                }
            }
            .foregroundStyle(.white.opacity(current ? 1 : hovering ? 0.85 : 0.6))
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background {
                if current {
                    shape.fill(.white.opacity(0.14)).matchedGeometryEffect(id: "device", in: selection)
                } else if hovering {
                    shape.fill(.white.opacity(0.06))
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(device.name)
        .accessibilityLabel(device.name)
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}

/// The Media tab's output panel: where sound plays, to switch as in the Sound tab, beside the Mac's
/// volume and the volume of the app that's playing.
public struct MediaOutputView: View {
    let mixer: Mixer
    /// The app playing, by bundle identifier.
    let appID: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection

    public init(mixer: Mixer, appID: String?) {
        self.mixer = mixer
        self.appID = appID
    }

    public var body: some View {
        let current = mixer.output?.id
        HStack(alignment: .top, spacing: 12) {
            ScrollView(.vertical) {
                VStack(spacing: 2) {
                    ForEach(mixer.outputs) { device in
                        DeviceRow(device: device, current: device.id == current, selection: selection) {
                            mixer.choose(device, for: .output)
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            .fadingEdges(.vertical, length: 6)
            VStack(spacing: 10) {
                if let output = mixer.output {
                    LevelSlider(
                        symbol: output.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        title: SoundView.shortName(output.name), level: output.isMuted ? 0 : output.level, tint: .white,
                        enabled: output.hasVolume
                    ) { mixer.setDeviceLevel($0, for: .output) }
                }
                if let app = mixer.apps.first(where: { $0.id == appID }) {
                    LevelSlider(
                        image: mixer.icon(for: app), title: app.name,
                        level: mixer.isMuted(app.id) ? 0 : mixer.level(of: app.id), tint: mixer.tint(for: app),
                        enabled: true
                    ) { mixer.setLevel($0, of: app.id) }
                }
            }
            .frame(width: 128)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: current)
        .onAppear { mixer.appeared() }
        .onDisappear { mixer.disappeared() }
    }
}

/// A slim sideways fader with what it controls and its level above it. Drag or click along it.
private struct LevelSlider: View {
    var symbol: String?
    var image: NSImage?
    let title: String
    let level: Double
    let tint: Color
    let enabled: Bool
    let set: (Double) -> Void

    init(
        symbol: String? = nil, image: NSImage? = nil, title: String, level: Double, tint: Color, enabled: Bool,
        set: @escaping (Double) -> Void
    ) {
        self.symbol = symbol
        self.image = image
        self.title = title
        self.level = level
        self.tint = tint
        self.enabled = enabled
        self.set = set
    }

    private var percent: Int { Int((min(max(level, 0), 1) * 100).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if let image {
                    Image(nsImage: image).resizable().frame(width: 13, height: 13)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).frame(width: 13)
                }
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
                Text("\(percent)%").monospacedDigit().foregroundStyle(.white.opacity(0.5))
            }
            .font(.system(size: 10.5, weight: .medium))
            GeometryReader { proxy in
                Capsule()
                    .fill(.white.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint).frame(width: max(6, proxy.size.width * min(max(level, 0), 1)))
                    }
                    .contentShape(Capsule())
                    .gesture(
                        DragGesture(minimumDistance: 0).onChanged { drag in
                            set(min(max(drag.location.x / max(proxy.size.width, 1), 0), 1))
                        },
                        isEnabled: enabled)
            }
            .frame(height: 6)
        }
        .opacity(enabled ? 1 : 0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(percent)%")
        .accessibilityAdjustableAction { direction in
            set(min(max(level + (direction == .increment ? 0.05 : -0.05), 0), 1))
        }
    }
}

extension Mixer {
    /// For the Sound tab's settings: what it does, and a way back to every app's own volume.
    public var settingsView: some View { MixerSettings(mixer: self) }
}

private struct MixerSettings: View {
    let mixer: Mixer

    var body: some View {
        LabeledContent {
            Button("Reset All") { mixer.resetAll() }
                .disabled(mixer.levels.isEmpty && mixer.muted.isEmpty)
        } label: {
            Text("App volumes")
            Text(
                "Turn each app up, down, or off in the Sound tab. It uses the waveform's system audio permission, "
                    + "and nothing is recorded.")
        }
    }
}

/// A tall rounded fader that fills from the bottom, like Control Center's, over the icon of what
/// it controls. Drag anywhere on it to set the level; click the icon to mute. It rises into place
/// when it appears, after the faders before it.
private struct Fader<Icon: View>: View {
    let title: String
    let level: Double
    let muted: Bool
    let tint: Color
    /// Shows a dot under the icon, like the Dock's for a running app.
    let playing: Bool
    let enabled: Bool
    let names: Bool
    /// Narrower, for a short notch.
    let slim: Bool
    /// Its place in the row, for the staggered entrance.
    let order: Int
    /// Put on the icon while muted; nil where the icon shows it already.
    let badge: String?
    let set: (Double) -> Void
    let toggleMute: () -> Void
    let reset: (() -> Void)?
    @ViewBuilder let icon: Icon

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var dragging = false
    @State private var risen = false

    private var percent: Int { Int((level * 100).rounded()) }

    var body: some View {
        VStack(spacing: 5) {
            track
            Button(action: toggleMute) {
                icon
                    .saturation(muted ? 0 : 1)
                    .opacity(muted ? 0.45 : 1)
                    .overlay(alignment: .bottomTrailing) {
                        if muted, let badge {
                            Image(systemName: badge)
                                .font(.system(size: 6.5, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 13, height: 13)
                                .background(Color(white: 0.22), in: Circle())
                                .overlay(Circle().strokeBorder(.black, lineWidth: 1))
                                .offset(x: 4, y: 4)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
            }
            .buttonStyle(PressableButtonStyle())
            .help(muted ? "Unmute \(title)" : "Mute \(title)")
            Circle()
                .fill(tint)
                .frame(width: 4, height: 4)
                .opacity(playing ? 0.9 : 0)
            if names {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(width: 54)
            }
        }
        .frame(width: slim ? 40 : 44)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: muted)
        .contextMenu {
            Button(muted ? "Unmute" : "Mute", action: toggleMute)
            if let reset { Button("Reset to 100%", action: reset) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(muted ? "Muted" : "\(percent)%")
        .accessibilityAdjustableAction { direction in
            set(min(max(level + (direction == .increment ? 0.05 : -0.05), 0), 1))
        }
        .accessibilityAction(named: muted ? "Unmute" : "Mute", toggleMute)
        .onAppear {
            let rise: Animation? =
                reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.78).delay(Double(order) * 0.04)
            withAnimation(rise) { risen = true }
        }
    }

    private var track: some View {
        GeometryReader { proxy in
            let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
            let shown = risen ? min(max(level, 0), 1) : 0
            ZStack(alignment: .bottom) {
                shape.fill(.white.opacity(hovering || dragging ? 0.13 : 0.08))
                fill
                    .frame(height: proxy.size.height * shown)
                    .animation(dragging ? nil : .easeOut(duration: 0.18), value: level)
                if hovering || dragging {
                    Text("\(percent)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(shown > 0.8 && !muted ? .black.opacity(0.7) : .white)
                        .padding(.top, 6)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(.opacity)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(dragging ? 0.3 : 0.1), lineWidth: 0.5))
            .contentShape(shape)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        dragging = true
                        set(min(max(1 - drag.location.y / max(proxy.size.height, 1), 0), 1))
                    }
                    .onEnded { _ in dragging = false },
                isEnabled: enabled)
        }
        .frame(width: (slim ? 30 : 34) + (dragging ? 4 : 0))
        .frame(maxHeight: 150)
        .opacity(enabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: dragging)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(muted ? "\(title): muted" : "\(title): \(percent)%")
    }

    /// The level: the tint with a gloss along its top and a lit edge; a faint gray while muted.
    private var fill: some View {
        Rectangle()
            .fill(muted ? AnyShapeStyle(Color.white.opacity(0.14)) : AnyShapeStyle(tint))
            .overlay {
                if !muted {
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0)], startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.45))
                }
            }
            .overlay(alignment: .top) {
                Rectangle().fill(.white.opacity(muted ? 0.12 : 0.65)).frame(height: 1)
            }
    }
}
