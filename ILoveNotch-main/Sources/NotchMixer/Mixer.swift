// SPDX-License-Identifier: MIT
import AppKit
import AudioToolbox
import CoreAudio
import Darwin
import NotchCore
import NotchFeatures
import Observation
import SwiftUI

/// An app that plays sound, with one fader for all of its processes (Chrome's helpers, Safari's
/// WebKit process).
public struct MixerApp: Identifiable, Hashable, Sendable {
    /// Its bundle identifier.
    public let id: String
    public let name: String
    /// Where it's installed, for its icon.
    public let url: URL
    /// Whether any of its processes is playing right now.
    public var isPlaying = false
    /// Its Core Audio process objects, sorted.
    var processes: [AudioObjectID] = []
    /// The output its sound goes to while it plays, when Core Audio says.
    var device: AudioObjectID?
}

/// Which way sound goes through a device.
public enum SoundDirection: Hashable, Sendable {
    case output, input

    var scope: AudioObjectPropertyScope {
        self == .output ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput
    }

    var defaultDevice: AudioObjectPropertySelector {
        self == .output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice
    }

    /// For a device that isn't one of the kinds `Mixer.symbol` knows.
    var fallbackSymbol: String { self == .output ? "speaker.wave.2.fill" : "mic.fill" }
}

/// A device that can play or record sound, for the device list.
public struct SoundDevice: Identifiable, Hashable, Sendable {
    public let id: AudioObjectID
    public let name: String
    /// Its kind as an SF Symbol: AirPods, headphones, a display, speakers, a microphone.
    public let symbol: String
}

/// The Mac's output or input device, for its fader.
public struct DeviceLevel: Hashable, Sendable {
    public var id: AudioObjectID
    public var name: String
    /// 0...1.
    public var level: Double
    public var isMuted: Bool
    /// False for a device without a volume of its own, such as a display over HDMI.
    public var hasVolume: Bool
    /// Its kind as an SF Symbol, such as AirPods; nil for plain speakers and microphones.
    public var symbol: String?
}

/// Everything in the Sound tab: the Mac's output and input devices, with a fader for each, and a
/// fader for each app playing sound. Turning an app down or muting it gives it an `AppTap` for as
/// long as it runs, which does its work only while the app plays; back at 100% it's left alone.
/// Everything runs on Core Audio's change notifications, never a timer, and while the tab is closed
/// and every app is at 100% nothing listens at all. Volumes are kept per app and apply whenever it
/// plays, until reset.
@MainActor
@Observable
public final class Mixer {
    /// Apps playing sound or with a volume of their own, in the order they first played. While the
    /// mixer is on screen, an app that stops stays, so faders don't vanish from under the pointer.
    public private(set) var apps: [MixerApp] = []
    public private(set) var output: DeviceLevel?
    public private(set) var input: DeviceLevel?
    /// Every device sound can play through, and record from: built-in, wired, Bluetooth, AirPlay.
    public private(set) var outputs: [SoundDevice] = []
    public private(set) var inputs: [SoundDevice] = []
    /// An app turned down here has played for a while without any tap hearing it: macOS hasn't let
    /// ILoveNotch record system audio.
    public private(set) var needsPermission = false
    /// The Sound tab is on. Off, every app plays at its own volume and nothing listens.
    public var isEnabled = false {
        didSet { if isEnabled != oldValue { update() } }
    }
    /// Volumes set here, 0...1 as the faders show them, by app; missing means 100%.
    public private(set) var levels: [String: Double] {
        didSet { defaults.set(levels, forKey: Key.levels) }
    }
    /// Apps muted here.
    public private(set) var muted: Set<String> {
        didSet { defaults.set(muted.sorted(), forKey: Key.muted) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    /// False in previews and tests: no Core Audio at all.
    @ObservationIgnored private let live: Bool
    @ObservationIgnored private var viewers = 0
    /// Every process Core Audio lists, with the app it plays for (nil for daemons and the like).
    @ObservationIgnored private var processes: [AudioObjectID: AppIdentity?] = [:]
    @ObservationIgnored private var processListeners: [AudioObjectID: [PropertyListener]] = [:]
    @ObservationIgnored private var systemListeners: [PropertyListener] = []
    /// The Mac's output and input devices, and listeners on their volume and mute.
    @ObservationIgnored private var devices: [SoundDirection: AudioObjectID] = [:]
    @ObservationIgnored private var deviceListeners: [SoundDirection: [PropertyListener]] = [:]
    private var outputDevice: AudioObjectID { devices[.output] ?? AudioObjectID(kAudioObjectUnknown) }
    /// The output the Mac just moved off, which quiet apps' taps leave on the next refresh.
    @ObservationIgnored private var followed: AudioObjectID?
    /// Apps with processes, by bundle identifier.
    @ObservationIgnored private var running: [String: MixerApp] = [:]
    @ObservationIgnored private var playing: Set<String> = []
    @ObservationIgnored private var taps: [String: AppTap] = [:]
    /// Taps that failed, so a notification doesn't retry the same one over and over.
    @ObservationIgnored private var failed: [String: AppTap.Mode] = [:]
    @ObservationIgnored private var retried: Set<String> = []
    @ObservationIgnored private var order: [String] = []
    /// Apps the open mixer has shown, which stay until it closes.
    @ObservationIgnored private var shown: Set<String> = []
    /// A tap heard sound this session, so macOS lets ILoveNotch record system audio.
    @ObservationIgnored private var heard = false
    @ObservationIgnored private var icons: [String: NSImage] = [:]
    @ObservationIgnored private var tints: [String: Color] = [:]

    public convenience init() {
        self.init(defaults: .standard, live: true)
    }

    init(defaults: UserDefaults, live: Bool) {
        self.defaults = defaults
        self.live = live
        levels = (defaults.dictionary(forKey: Key.levels) as? [String: Double]) ?? [:]
        muted = Set(defaults.stringArray(forKey: Key.muted) ?? [])
    }

    // MARK: Faders

    public func level(of id: String) -> Double { levels[id] ?? 1 }

    public func isMuted(_ id: String) -> Bool { muted.contains(id) }

    /// Whether the app has a volume of its own here.
    public func isAdjusted(_ id: String) -> Bool { levels[id] != nil || muted.contains(id) }

    /// Sets an app's volume, in whole percent; 100% hands the app back to its own volume.
    public func setLevel(_ level: Double, of id: String) {
        let level = (min(max(level, 0), 1) * 100).rounded() / 100
        guard level != self.level(of: id) else { return }
        let before = wantedMode(id)
        levels[id] = level < 1 ? level : nil
        // Mid-drag only the gain moves; the tap changes when the level reaches 0 or 100%.
        if wantedMode(id) == before, isListening, failed[id] == nil {
            taps[id]?.gain = gain(of: id)
        } else {
            retry(id)
        }
    }

    public func toggleMute(_ id: String) {
        if muted.contains(id) { muted.remove(id) } else { muted.insert(id) }
        retry(id)
    }

    /// Back to 100% and unmuted: the app plays at its own volume again.
    public func reset(_ id: String) {
        levels[id] = nil
        muted.remove(id)
        retry(id)
    }

    public func resetAll() {
        levels = [:]
        muted = []
        failed = [:]
        retried = []
        update()
    }

    /// A change the user made gives a tap that failed another try.
    private func retry(_ id: String) {
        failed[id] = nil
        retried.remove(id)
        update()
    }

    /// Sets the Mac's output or input volume; raising a muted one unmutes it, as the volume keys do.
    public func setDeviceLevel(_ level: Double, for direction: SoundDirection) {
        guard let device = devices[direction], device != kAudioObjectUnknown else { return }
        let scope = direction.scope
        if self.level(direction)?.isMuted == true, level > 0 {
            device.write(kAudioDevicePropertyMute, scope: scope, UInt32(0))
        }
        device.write(Self.volume, scope: scope, Float32(min(max(level, 0), 1)))
        read(direction)  // at once, so the fader keeps up with the pointer
    }

    public func toggleDeviceMute(_ direction: SoundDirection) {
        guard let current = level(direction), let device = devices[direction] else { return }
        let muted: UInt32 = current.isMuted ? 0 : 1
        device.write(kAudioDevicePropertyMute, scope: direction.scope, muted)
        read(direction)
    }

    /// Makes `device` the Mac's output or input, as picking it in Control Center does.
    public func choose(_ device: SoundDevice, for direction: SoundDirection) {
        guard live, device.id != devices[direction] else { return }
        AudioObjectID.system.write(direction.defaultDevice, device.id)
    }

    private func level(_ direction: SoundDirection) -> DeviceLevel? { direction == .output ? output : input }

    public func icon(for app: MixerApp) -> NSImage {
        if let icon = icons[app.id] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: app.url.path)
        icons[app.id] = icon
        return icon
    }

    /// The app icon's color, for its fader.
    public func tint(for app: MixerApp) -> Color {
        if let tint = tints[app.id] { return tint }
        var rect = CGRect(x: 0, y: 0, width: 64, height: 64)
        let image = icon(for: app).cgImage(forProposedRect: &rect, context: nil, hints: nil)
        let tint = image.flatMap(Self.tint(of:))?.color ?? .white
        tints[app.id] = tint
        return tint
    }

    /// An icon's most common vivid color, lifted to read on black: Chrome's red or green rather than
    /// the brown they average to. Nil for a gray icon.
    nonisolated static func tint(of image: CGImage) -> RGB? {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                let context = CGContext(
                    data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        // Opaque, vivid pixels vote for one of twelve hues, the more vivid the louder.
        var votes = [Double](repeating: 0, count: 12)
        var sums = [[Double]](repeating: [0, 0, 0], count: 12)
        for pixel in stride(from: 0, to: pixels.count, by: 4) where pixels[pixel + 3] > 150 {
            let alpha = Double(pixels[pixel + 3])
            let rgb = (0..<3).map { Double(pixels[pixel + $0]) / alpha }
            let color = NSColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
            let vivid = color.saturationComponent * color.brightnessComponent
            guard color.saturationComponent > 0.35, color.brightnessComponent > 0.3 else { continue }
            let hue = Int((color.hueComponent * 12).rounded()) % 12  // red sits at both ends of the wheel
            votes[hue] += vivid
            for channel in 0..<3 { sums[hue][channel] += rgb[channel] * vivid }
        }
        guard let winner = votes.indices.max(by: { votes[$0] < votes[$1] }), votes[winner] > 0 else { return nil }
        let mean = sums[winner].map { $0 / votes[winner] }
        let color = NSColor(srgbRed: mean[0], green: mean[1], blue: mean[2], alpha: 1)
        let lifted = NSColor(
            hue: color.hueComponent, saturation: max(color.saturationComponent, 0.55),
            brightness: max(color.brightnessComponent, 0.85), alpha: 1)
        guard let sRGB = lifted.usingColorSpace(.sRGB) else { return nil }
        return RGB(red: sRGB.redComponent, green: sRGB.greenComponent, blue: sRGB.blueComponent)
    }

    /// The mixer view calls these as it comes on and off screen, so its list is live while seen.
    func appeared() {
        viewers += 1
        if viewers == 1 { update() }
    }

    func disappeared() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        shown = []
        update()
    }

    /// Shows these devices and faders without Core Audio, for previews and snapshots.
    func preview(
        apps: [MixerApp], output: DeviceLevel?, input: DeviceLevel? = nil, outputs: [SoundDevice] = [],
        inputs: [SoundDevice] = []
    ) {
        self.apps = apps
        self.output = output
        self.input = input
        self.outputs = outputs
        self.inputs = inputs
    }

    // MARK: Decisions

    /// What an app's tap does: nothing at 100%, mute it at its source while it's muted or at 0, and
    /// otherwise play it back at its volume on the output it uses.
    nonisolated static func mode(level: Double, muted: Bool, device: AudioObjectID) -> AppTap.Mode? {
        if muted || level <= 0 { return .silence }
        guard level < 1, device != kAudioObjectUnknown else { return nil }
        return .mix(device: device)
    }

    /// The fader's position squared: halfway is a quarter of the loudness, about 12 dB down, which
    /// hearing takes as about half as loud.
    nonisolated static func gain(level: Double, muted: Bool) -> Float {
        muted ? 0 : Float(min(max(level, 0), 1) * min(max(level, 0), 1))
    }

    /// The output an app plays on, from the devices its playing processes use: the Mac's own output
    /// if it's one of them, else the first other output the Mac lists. An app's private devices (a
    /// voice-processing aggregate for a call, say) don't count, and nor does which of its processes
    /// Core Audio happens to list first, so the answer doesn't flip and rebuild the tap.
    nonisolated static func device(
        among used: Set<AudioObjectID>, outputs: Set<AudioObjectID>, current: AudioObjectID
    ) -> AudioObjectID? {
        used.contains(current) ? current : used.intersection(outputs).min()
    }

    private func gain(of id: String) -> Float { Self.gain(level: level(of: id), muted: isMuted(id)) }

    private func wantedMode(_ id: String) -> AppTap.Mode? {
        guard isListening, let app = running[id] else { return nil }
        return Self.mode(level: level(of: id), muted: isMuted(id), device: app.device ?? outputDevice)
    }

    // MARK: Listening

    private var isListening: Bool { !systemListeners.isEmpty }

    /// Starts or stops listening to Core Audio as needed, then brings everything in line.
    private func update() {
        guard live else { return }
        let wanted = isEnabled && (viewers > 0 || !levels.isEmpty || !muted.isEmpty)
        if wanted, !isListening { startListening() }
        if !wanted, isListening { stopListening() }
        refresh()
    }

    private func startListening() {
        systemListeners = [
            PropertyListener(.system, kAudioHardwarePropertyProcessObjectList) { [weak self] in
                self?.refreshProcesses()
            },
            PropertyListener(.system, kAudioHardwarePropertyDevices) { [weak self] in self?.refreshDevices() },
            PropertyListener(.system, kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
                self?.follow(.output)
                self?.refresh()
            },
            PropertyListener(.system, kAudioHardwarePropertyDefaultInputDevice) { [weak self] in
                self?.follow(.input)
            },
        ].compactMap { $0 }
        refreshDevices()
        follow(.output)
        follow(.input)
        refreshProcesses()
    }

    private func stopListening() {
        let all = systemListeners + deviceListeners.values.joined() + processListeners.values.joined()
        for listener in all { listener.cancel() }
        systemListeners = []
        deviceListeners = [:]
        processListeners = [:]
        processes = [:]
        devices = [:]
        output = nil
        input = nil
        outputs = []
        inputs = []
        playing = []
        needsPermission = false
    }

    /// A process's properties that say it started or stopped playing, or moved to another output.
    private static let watched = [
        kAudioProcessPropertyIsRunning, kAudioProcessPropertyIsRunningOutput, kAudioProcessPropertyDevices,
    ]

    /// Follows the processes Core Audio knows as they come and go, with the app each plays for.
    private func refreshProcesses() {
        let current = Set(AudioObjectID.system.readList(kAudioHardwarePropertyProcessObjectList))
        for object in processes.keys where !current.contains(object) {
            for listener in processListeners.removeValue(forKey: object) ?? [] { listener.cancel() }
            processes.removeValue(forKey: object)
        }
        for object in current where processes.index(forKey: object) == nil {
            let app = AppIdentity(process: object)
            processes.updateValue(app, forKey: object)
            guard app != nil else { continue }
            // macOS 26 announces a process starting and stopping IO (IsRunning) but not its output
            // flag, which refresh reads each time instead.
            processListeners[object] = Self.watched.compactMap {
                PropertyListener(object, $0) { [weak self] in self?.refresh() }
            }
        }
        refresh()
    }

    /// Groups processes into apps, updates the faders, and brings the taps in line.
    private func refresh() {
        var found: [String: MixerApp] = [:]
        var used: [String: Set<AudioObjectID>] = [:]  // the outputs each app's playing processes use
        for (object, app) in processes {
            guard let app else { continue }
            var entry = found[app.id] ?? MixerApp(id: app.id, name: app.name, url: app.url)
            entry.processes.append(object)
            if object.read(kAudioProcessPropertyIsRunningOutput, default: UInt32(0)) != 0 {
                entry.isPlaying = true
                used[app.id, default: []].formUnion(
                    object.readList(kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput))
            }
            found[app.id] = entry
        }
        let real = Set(outputs.map(\.id))
        for id in found.keys {
            found[id]?.processes.sort()
            found[id]?.device = Self.device(among: used[id] ?? [], outputs: real, current: outputDevice)
            // A quiet app keeps the output it last played on, so pausing doesn't move its tap, unless
            // that's no longer the Mac's output: then it follows, as the app will when it plays.
            let last = running[id]?.device
            if found[id]?.device == nil, last != followed { found[id]?.device = last }
        }
        followed = nil
        running = found
        let nowPlaying = Set(found.values.filter(\.isPlaying).map(\.id))
        let started = nowPlaying.subtracting(playing)
        for id in playing.subtracting(nowPlaying) { quieted(id) }
        playing = nowPlaying
        for id in found.keys.sorted() where (nowPlaying.contains(id) || isAdjusted(id)) && !order.contains(id) {
            order.append(id)
        }
        let visible = order.filter { id in
            found[id] != nil && (playing.contains(id) || isAdjusted(id) || shown.contains(id))
        }
        if viewers > 0 { shown.formUnion(visible) }
        let apps = visible.compactMap { found[$0] }
        if apps != self.apps { self.apps = apps }
        reconcile()
        for id in started { watch(id) }
    }

    /// Makes every app's tap what its volume calls for. A tap that changes is built before the old
    /// one goes, so the app never plays at full volume in between; one whose app gains or loses a
    /// helper follows it without stopping.
    private func reconcile() {
        var wanted: [String: AppTap.Mode] = [:]
        for id in running.keys { wanted[id] = wantedMode(id) }
        for id in failed.keys where wanted[id] != failed[id] { failed[id] = nil }
        for (id, tap) in taps {
            guard let mode = wanted[id], let app = running[id] else {
                taps[id] = nil
                continue
            }
            if mode != tap.mode {
                install(id, mode, because: "it changed from \(tap.mode)")
            } else if app.processes != tap.processes, !tap.retarget(app.processes) {
                install(id, mode, because: "its processes changed")
            }
        }
        for (id, mode) in wanted where taps[id] == nil && failed[id] != mode { install(id, mode, because: "new") }
        for (id, tap) in taps { tap.gain = gain(of: id) }
    }

    /// Builds the app's tap, replacing any it has; a failed one leaves the app at its own volume.
    private func install(_ id: String, _ mode: AppTap.Mode, because why: String) {
        guard let app = running[id] else { return }
        let what = String(describing: mode)
        Log.mixer.info("\(app.name, privacy: .public): \(what, privacy: .public), \(why, privacy: .public)")
        let tap = AppTap(
            app: app.name, processes: app.processes, mode: mode, gain: gain(of: id), replacing: heard
        ) { [weak self] in self?.tapHeard() }
        do {
            try tap.start()
        } catch {
            Log.mixer.error("\(app.name, privacy: .public): \(String(describing: error), privacy: .public)")
            failed[id] = mode
            taps[id] = nil
            return
        }
        taps[id] = tap
        if playing.contains(id) { watch(id) }
    }

    /// Checks on a mixing tap a moment after its app starts playing: if the tap's IO hasn't run,
    /// it's built once more, then the app is left at its own volume; if the IO runs but hears
    /// nothing, macOS hasn't allowed recording. A quiet app's tap is never judged: its IO waits.
    private func watch(_ id: String) {
        guard let tap = taps[id], case .mix = tap.mode else { return }
        let before = tap.cycles
        Task { [weak self, weak tap] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, let tap, taps[id] === tap, playing.contains(id) else { return }
            if tap.cycles != before {
                retried.remove(id)
                guard !heard else { return }
                Log.mixer.info("\(id, privacy: .public) plays, but no tap has heard anything yet")
                needsPermission = true
            } else if retried.insert(id).inserted {
                Log.mixer.error("\(id, privacy: .public)'s tap didn't run while it played; building it again")
                install(id, tap.mode, because: "the last one didn't run")
            } else {
                Log.mixer.error("\(id, privacy: .public)'s tap didn't run while it played; leaving it alone")
                failed[id] = tap.mode
                taps[id] = nil
            }
        }
    }

    /// A moment after an app goes quiet (and stays quiet, so a gap between songs doesn't count),
    /// its tap stops its IO until the app plays again.
    private func quieted(_ id: String) {
        guard let tap = taps[id], case .mix = tap.mode else { return }
        Task { [weak self, weak tap] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, let tap, taps[id] === tap, !playing.contains(id) else { return }
            Log.mixer.info("\(id, privacy: .public) went quiet; its tap waits for it to play")
            tap.rearm()
        }
    }

    /// Some tap heard sound, so macOS allows recording: mute the mixing apps at their source.
    private func tapHeard() {
        needsPermission = false
        guard !heard else { return }
        heard = true
        Log.mixer.info("A tap heard sound; apps play through their taps now")
        for (id, tap) in taps where !tap.replace() { install(id, tap.mode, because: "it couldn't mute its app") }
    }

    // MARK: Devices

    private static let volume = kAudioHardwareServiceDeviceProperty_VirtualMainVolume
    /// What a device's fader shows: its volume, its mute, and what's plugged in (headphones or not).
    private static let levelProperties = [volume, kAudioDevicePropertyMute, kAudioDevicePropertyDataSource]

    /// Every device that can be the Mac's output or input, as Control Center lists them. A Bluetooth
    /// device joins while it's connected.
    private func refreshDevices() {
        var outputs: [SoundDevice] = []
        var inputs: [SoundDevice] = []
        for device in AudioObjectID.system.readList(kAudioHardwarePropertyDevices) {
            // The mixer's and the waveform's own aggregate devices, which only ILoveNotch sees.
            guard let uid = device.readString(kAudioDevicePropertyDeviceUID), !uid.hasPrefix("cafe.opennotch."),
                device.read(kAudioDevicePropertyIsHidden, default: UInt32(0)) == 0
            else { continue }
            let name = device.readString(kAudioObjectPropertyName) ?? uid
            for direction in [SoundDirection.output, .input]
            where device.read(kAudioDevicePropertyDeviceCanBeDefaultDevice, scope: direction.scope, default: UInt32(0))
                != 0
            {
                let symbol = Self.symbol(of: device, named: name, direction) ?? direction.fallbackSymbol
                let entry = SoundDevice(id: device, name: name, symbol: symbol)
                if direction == .output { outputs.append(entry) } else { inputs.append(entry) }
            }
        }
        if outputs != self.outputs { self.outputs = outputs }
        if inputs != self.inputs { self.inputs = inputs }
    }

    /// Moves to the Mac's current output or input device and listens to its volume and mute.
    private func follow(_ direction: SoundDirection) {
        for listener in deviceListeners[direction] ?? [] { listener.cancel() }
        let device = AudioObjectID.system.read(direction.defaultDevice, default: AudioObjectID(kAudioObjectUnknown))
        if direction == .output, let old = devices[.output], old != device { followed = old }
        devices[direction] = device
        let scope = direction.scope
        deviceListeners[direction] = Self.levelProperties.compactMap {
            device.has($0, scope: scope)
                ? PropertyListener(device, $0, scope: scope) { [weak self] in self?.read(direction) } : nil
        }
        read(direction)
    }

    private func read(_ direction: SoundDirection) {
        let device = devices[direction] ?? AudioObjectID(kAudioObjectUnknown)
        var level: DeviceLevel?
        if device != kAudioObjectUnknown {
            let scope = direction.scope
            let name = device.readString(kAudioObjectPropertyName) ?? (direction == .output ? "Output" : "Input")
            level = DeviceLevel(
                id: device, name: name, level: Double(device.read(Self.volume, scope: scope, default: Float32(1))),
                isMuted: device.read(kAudioDevicePropertyMute, scope: scope, default: UInt32(0)) != 0,
                hasVolume: device.has(Self.volume, scope: scope),
                symbol: Self.symbol(of: device, named: name, direction))
        }
        switch direction {
        case .output: if level != output { output = level }
        case .input: if level != input { input = level }
        }
    }

    private static func symbol(of device: AudioObjectID, named name: String, _ direction: SoundDirection) -> String? {
        symbol(
            transport: device.read(kAudioDevicePropertyTransportType, default: UInt32(0)),
            dataSource: device.read(kAudioDevicePropertyDataSource, scope: direction.scope, default: UInt32(0)),
            name: name)
    }

    /// A device's kind as an SF Symbol: AirPods and Beats by name, an iPhone's microphone, headphones
    /// in the jack or over Bluetooth, AirPlay, a display; nil for plain speakers and microphones.
    nonisolated static func symbol(transport: UInt32, dataSource: UInt32, name: String) -> String? {
        let name = name.lowercased()
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods pro") { return "airpodspro" }
        if name.contains("airpods") { return "airpods" }
        if name.contains("beats") { return "beats.headphones" }
        if name.contains("iphone") { return "iphone" }
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
        case kAudioDeviceTransportTypeBuiltIn where dataSource == 0x6864_706E: return "headphones"  // 'hdpn'
        default: return nil
        }
    }

    private enum Key {
        static let levels = "mixer.levels"
        static let muted = "mixer.muted"
    }
}

/// The app a process plays for.
struct AppIdentity: Hashable {
    /// Its bundle identifier.
    let id: String
    let name: String
    let url: URL
}

extension AppIdentity {
    /// Nil for a process with no app to show: daemons, macOS's own services (Control Center, the
    /// charging chime), background-only apps, and ILoveNotch itself.
    @MainActor
    init?(process: AudioObjectID) {
        let pid = process.read(kAudioProcessPropertyPID, default: pid_t(-1))
        guard pid > 0, pid != getpid(), let found = Self.appURL(for: pid), let bundle = Bundle(url: found),
            let id = bundle.bundleIdentifier, id != Bundle.main.bundleIdentifier,
            bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool != true
        else { return nil }
        // Where Launch Services has it, rather than a copy it runs from (Chrome runs from one).
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) ?? found
        guard !url.path.hasPrefix("/System/Library/CoreServices/") else { return nil }
        // Finder's name for it, which ends in ".app" when Finder shows every extension.
        let name = FileManager.default.displayName(atPath: url.path)
        self.init(id: id, name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name, url: url)
    }

    /// The app bundle behind `pid`: the app macOS holds responsible for it (Safari for its WebKit
    /// processes), else the outermost app bundle around its executable (Chrome for its helpers).
    @MainActor
    static func appURL(for pid: pid_t) -> URL? {
        if let owner = responsible?(pid), owner > 0,
            let url = NSRunningApplication(processIdentifier: owner)?.bundleURL
                ?? executable(owner).flatMap({ appBundle(in: $0, outermost: false) })
        {
            return url
        }
        return executable(pid).flatMap { appBundle(in: $0, outermost: true) }
            ?? NSRunningApplication(processIdentifier: pid)?.bundleURL
    }

    /// The outermost or innermost `.app` bundle in a path.
    static func appBundle(in path: String, outermost: Bool) -> URL? {
        let parts = path.split(separator: "/")
        let bundles = parts.indices.filter { parts[$0].hasSuffix(".app") }
        guard let end = outermost ? bundles.first : bundles.last else { return nil }
        return URL(filePath: "/" + parts[...end].joined(separator: "/"), directoryHint: .isDirectory)
    }

    private static func executable(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)  // PROC_PIDPATHINFO_MAXSIZE
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    /// Which process macOS holds responsible for another: an XPC service's or helper's app. A
    /// private call, stable for years; if it's ever gone, the path fallback takes over.
    private static let responsible: (@convention(c) (pid_t) -> pid_t)? = dlsym(
        UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid"
    ).map { unsafeBitCast($0, to: (@convention(c) (pid_t) -> pid_t).self) }
}
