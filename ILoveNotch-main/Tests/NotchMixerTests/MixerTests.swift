// SPDX-License-Identifier: MIT
import AppKit
import CoreAudio
import SwiftUI
import Testing

@testable import NotchMixer

/// An `AudioBufferList` of float buffers for one IO cycle, freed with the test.
private final class Buffers {
    let list: UnsafeMutableAudioBufferListPointer
    private var storage: [UnsafeMutablePointer<Float>] = []

    init(_ buffers: [(channels: Int, samples: [Float])]) {
        list = AudioBufferList.allocate(maximumBuffers: buffers.count)
        for (index, buffer) in buffers.enumerated() {
            let data = UnsafeMutablePointer<Float>.allocate(capacity: max(buffer.samples.count, 1))
            data.initialize(from: buffer.samples, count: buffer.samples.count)
            storage.append(data)
            list[index] = AudioBuffer(
                mNumberChannels: UInt32(buffer.channels), mDataByteSize: UInt32(buffer.samples.count * 4), mData: data)
        }
    }

    /// Output buffers of these channel counts, `frames` long, filled with junk the render must replace.
    convenience init(channels: [Int], frames: Int) {
        self.init(channels.map { ($0, [Float](repeating: 9, count: $0 * frames)) })
    }

    func samples(_ index: Int) -> [Float] {
        Array(UnsafeBufferPointer(start: storage[index], count: Int(list[index].mDataByteSize) / 4))
    }

    deinit {
        for data in storage { data.deallocate() }
        free(list.unsafeMutablePointer)
    }
}

struct RenderTests {
    /// Interleaved stereo: left rises 0.1, 0.2…, right is its negative.
    private let stereo: [Float] = (1...4).flatMap { [Float($0) / 10, -Float($0) / 10] }

    private func state(gain: Float, applied: Float? = nil, tap: Int32 = 0, replacing: Bool = true) -> RenderState {
        var state = RenderState()
        state.gain = gain
        state.applied = applied ?? gain
        state.tapBuffer = tap
        state.tapChannels = 2
        state.replacing = replacing ? 1 : 0
        return state
    }

    @discardableResult
    private func cycle(_ input: Buffers, _ output: Buffers, _ state: inout RenderState) -> Bool {
        withUnsafeMutablePointer(to: &state) {
            AppTap.render(input.list.unsafePointer, into: output.list.unsafeMutablePointer, state: $0)
        }
    }

    @Test func playsTheTapAtItsGain() {
        let input = Buffers([(2, stereo)])
        let output = Buffers(channels: [2], frames: 4)
        var state = state(gain: 0.25)
        cycle(input, output, &state)
        #expect(output.samples(0) == stereo.map { $0 * 0.25 })
    }

    @Test func aNewGainRampsAcrossTheBufferThenHolds() {
        let input = Buffers([(2, [Float](repeating: 1, count: 8))])
        let output = Buffers(channels: [2], frames: 4)
        var state = state(gain: 0, applied: 1)
        cycle(input, output, &state)
        #expect(output.samples(0) == [1, 1, 0.75, 0.75, 0.5, 0.5, 0.25, 0.25], "from 1 toward 0, no jump")
        cycle(input, output, &state)
        #expect(output.samples(0).allSatisfy { $0 == 0 }, "the next buffer sits at the new gain")
    }

    @Test func separateChannelBuffersGetLeftAndRight() {
        let input = Buffers([(2, stereo)])
        let output = Buffers(channels: [1, 1], frames: 4)
        var state = state(gain: 1)
        cycle(input, output, &state)
        #expect(output.samples(0) == [0.1, 0.2, 0.3, 0.4])
        #expect(output.samples(1) == [-0.1, -0.2, -0.3, -0.4])
    }

    @Test func aMonoOutputHearsBothSides() {
        let input = Buffers([(2, [0.2, 0.4, 0.6, 0.8])])
        let output = Buffers(channels: [1], frames: 2)
        var state = state(gain: 1)
        cycle(input, output, &state)
        #expect(output.samples(0).map { ($0 * 100).rounded() } == [30, 70])
    }

    @Test func channelsPastStereoAreSilent() {
        let input = Buffers([(2, stereo)])
        let output = Buffers(channels: [4], frames: 4)
        var state = state(gain: 1)
        cycle(input, output, &state)
        let samples = output.samples(0)
        #expect(stride(from: 0, to: 16, by: 4).map { samples[$0] } == [0.1, 0.2, 0.3, 0.4])
        #expect(stride(from: 2, to: 16, by: 4).allSatisfy { samples[$0] == 0 && samples[$0 + 1] == 0 })
    }

    @Test func onlyTheTapIsPlayedNeverTheDevicesOwnInput() {
        // Buffer 0 is the output device's microphone, loud; buffer 1 is the tap.
        let input = Buffers([(1, [1, 1, 1, 1]), (2, stereo)])
        let output = Buffers(channels: [2], frames: 4)
        var state = state(gain: 1, tap: 1)
        cycle(input, output, &state)
        #expect(output.samples(0) == stereo)
    }

    @Test func silentUntilTheAppIsMutedAtItsSource() {
        let quiet = Buffers([(2, [Float](repeating: 0, count: 8))])
        let output = Buffers(channels: [2], frames: 4)
        var state = state(gain: 1, replacing: false)
        #expect(!cycle(quiet, output, &state), "silence isn't hearing anything")
        let sound = Buffers([(2, stereo)])
        #expect(cycle(sound, output, &state), "the first sound is reported")
        #expect(output.samples(0).allSatisfy { $0 == 0 }, "while the app still plays itself, nothing twice")
        #expect(!cycle(sound, output, &state), "reported once")
        state.replacing = 1
        cycle(sound, output, &state)
        #expect(output.samples(0) == stereo)
    }

    @Test func anUnexpectedTapBufferIsSilence() {
        let output = Buffers(channels: [2], frames: 4)
        var wrongShape = state(gain: 1)
        cycle(Buffers([(1, [1, 1, 1, 1])]), output, &wrongShape)
        #expect(output.samples(0).allSatisfy { $0 == 0 })
        var missing = state(gain: 1, tap: 3)
        cycle(Buffers([(2, stereo)]), output, &missing)
        #expect(output.samples(0).allSatisfy { $0 == 0 })
    }

    @Test func brokenSamplesNeverReachTheSpeakers() {
        let input = Buffers([(2, [.nan, .infinity, 3, -3])])
        let output = Buffers(channels: [2], frames: 2)
        var state = state(gain: 1)
        cycle(input, output, &state)
        #expect(output.samples(0) == [0, 0, 1, -1])
    }
}

struct TapBufferTests {
    @Test func theTapFollowsTheDevicesInputs() {
        #expect(AppTap.tapBuffer(aggregate: [2], device: [], tapChannels: 2, terminals: { [] }) == 0)
        #expect(AppTap.tapBuffer(aggregate: [1, 2], device: [1], tapChannels: 2, terminals: { [] }) == 1)
    }

    @Test func anyOtherLayoutIsRefused() {
        #expect(AppTap.tapBuffer(aggregate: [2], device: [1], tapChannels: 2, terminals: { [] }) == nil)
        #expect(AppTap.tapBuffer(aggregate: [2, 1], device: [1], tapChannels: 2, terminals: { [] }) == nil)
        #expect(AppTap.tapBuffer(aggregate: [], device: [], tapChannels: 0, terminals: { [] }) == nil)
    }

    @Test func aStereoInputLikeTheTapNeedsTheTerminalTypesToAgree() {
        let microphone: UInt32 = 0x6D69_6372  // 'micr'
        #expect(AppTap.tapBuffer(aggregate: [2, 2], device: [2], tapChannels: 2, terminals: { [microphone, 0] }) == 1)
        #expect(AppTap.tapBuffer(aggregate: [2, 2], device: [2], tapChannels: 2, terminals: { [0, 0] }) == nil)
        #expect(AppTap.tapBuffer(aggregate: [2, 2], device: [2], tapChannels: 2, terminals: { [nil, 0] }) == nil)
        #expect(AppTap.tapBuffer(aggregate: [2, 2], device: [2], tapChannels: 2, terminals: { [microphone] }) == nil)
    }
}

struct MixerDecisionTests {
    private let speakers = AudioObjectID(72)

    @Test func appsAtFullVolumeAreLeftAlone() {
        #expect(Mixer.mode(level: 1, muted: false, device: speakers) == nil)
    }

    @Test func mutedAppsAreSilencedAtTheSource() {
        #expect(Mixer.mode(level: 1, muted: true, device: speakers) == .silence)
        #expect(Mixer.mode(level: 0, muted: false, device: speakers) == .silence)
    }

    @Test func turnedDownAppsMixOnTheOutputTheyUse() {
        #expect(Mixer.mode(level: 0.4, muted: false, device: speakers) == .mix(device: speakers))
        #expect(Mixer.mode(level: 0.4, muted: false, device: AudioObjectID(kAudioObjectUnknown)) == nil)
    }

    @Test func anAppPlaysOnTheMacsOutputOrAnotherRealOneNeverAPrivateDevice() {
        let speakers: AudioObjectID = 72
        let airPods: AudioObjectID = 80
        let voiceProcessing: AudioObjectID = 140  // an app's own aggregate for a call
        let outputs: Set<AudioObjectID> = [speakers, airPods]
        #expect(Mixer.device(among: [voiceProcessing, speakers], outputs: outputs, current: speakers) == speakers)
        #expect(Mixer.device(among: [voiceProcessing, airPods], outputs: outputs, current: speakers) == airPods)
        #expect(Mixer.device(among: [voiceProcessing], outputs: outputs, current: speakers) == nil)
        #expect(Mixer.device(among: [], outputs: outputs, current: speakers) == nil)
    }

    @Test func halfwayIsAQuarterOfTheLoudness() {
        #expect(Mixer.gain(level: 0.5, muted: false) == 0.25)
        #expect(Mixer.gain(level: 1, muted: true) == 0)
        #expect(Mixer.gain(level: 2, muted: false) == 1)
    }

    @Test func helpersBelongToTheOutermostAppAndAppsToTheirOwnBundle() {
        let helper =
            "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/153/"
            + "Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"
        #expect(AppIdentity.appBundle(in: helper, outermost: true)?.path == "/Applications/Google Chrome.app")
        let simulator = "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app/Contents/MacOS/Simulator"
        #expect(AppIdentity.appBundle(in: simulator, outermost: false)?.lastPathComponent == "Simulator.app")
        #expect(AppIdentity.appBundle(in: "/usr/libexec/audiomxd", outermost: true) == nil)
        let clone = "/tmp/clone/Google Chrome.app.bundle/Contents/MacOS/Google Chrome"
        #expect(AppIdentity.appBundle(in: clone, outermost: true) == nil)
    }

    @Test func devicesShowWhatTheyAre() {
        let bluetooth = kAudioDeviceTransportTypeBluetooth
        let builtIn = kAudioDeviceTransportTypeBuiltIn
        #expect(Mixer.symbol(transport: bluetooth, dataSource: 0, name: "Niyam's AirPods Pro") == "airpodspro")
        #expect(Mixer.symbol(transport: bluetooth, dataSource: 0, name: "AirPods Max") == "airpodsmax")
        #expect(Mixer.symbol(transport: bluetooth, dataSource: 0, name: "WH-1000XM5") == "headphones")
        #expect(Mixer.symbol(transport: builtIn, dataSource: 0x6864_706E, name: "External Headphones") == "headphones")
        #expect(Mixer.symbol(transport: builtIn, dataSource: 0x6973_706B, name: "MacBook Pro Speakers") == nil)
        #expect(Mixer.symbol(transport: kAudioDeviceTransportTypeHDMI, dataSource: 0, name: "LG HDR 4K") == "tv")
        let continuity = kAudioDeviceTransportTypeContinuityCaptureWireless
        #expect(Mixer.symbol(transport: continuity, dataSource: 0, name: "Niyam's iPhone Microphone") == "iphone")
        #expect(Mixer.symbol(transport: builtIn, dataSource: 0, name: "MacBook Pro Microphone") == nil)
    }

    @Test func aFaderTakesItsIconsMostCommonVividColor() throws {
        func icon(_ stripes: [(CGColor, Int)]) throws -> CGImage {
            let context = try #require(
                CGContext(
                    data: nil, width: 30, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            var x = 0
            for (color, width) in stripes {
                context.setFillColor(color)
                context.fill(CGRect(x: x, y: 0, width: width, height: 30))
                x += width
            }
            return try #require(context.makeImage())
        }
        let red = CGColor(srgbRed: 0.86, green: 0.2, blue: 0.16, alpha: 1)
        let green = CGColor(srgbRed: 0.2, green: 0.66, blue: 0.33, alpha: 1)
        let yellow = CGColor(srgbRed: 0.98, green: 0.74, blue: 0.02, alpha: 1)
        let blue = CGColor(srgbRed: 0.1, green: 0.45, blue: 0.9, alpha: 1)
        let chrome = try #require(Mixer.tint(of: try icon([(red, 10), (green, 10), (yellow, 10)])))
        let color = NSColor(srgbRed: chrome.red, green: chrome.green, blue: chrome.blue, alpha: 1)
        #expect(color.saturationComponent > 0.5, "one of the colors, not the brown they average to")
        let mostlyBlue = try #require(Mixer.tint(of: try icon([(blue, 20), (red, 10)])))
        #expect(mostlyBlue.blue > mostlyBlue.red)
        #expect(Mixer.tint(of: try icon([(CGColor(gray: 0.5, alpha: 1), 30)])) == nil, "gray icons get white")
    }

    @Test func deviceNamesShortenToFitUnderAFader() {
        #expect(SoundView.shortName("Niyam's AirPods Pro") == "AirPods Pro")
        #expect(SoundView.shortName("MacBook Pro Speakers") == "Speakers")
        #expect(SoundView.shortName("MacBook Air Microphone") == "Microphone")
        #expect(SoundView.shortName("External Headphones") == "Headphones")
        #expect(SoundView.shortName("Niyam’s iPhone Microphone") == "iPhone Microphone")
        #expect(SoundView.shortName("Studio Display Speakers") == "Studio Display Speakers")
        #expect(SoundView.shortName("LG HDR 4K") == "LG HDR 4K")
    }
}

@MainActor
struct MixerModelTests {
    @Test func volumesAreKeptInWholePercentAndAHundredForgetsThem() {
        let defaults = UserDefaults(suiteName: "Mixer-\(UUID())")!
        let mixer = Mixer(defaults: defaults, live: false)
        mixer.setLevel(0.504, of: "com.spotify.client")
        mixer.toggleMute("com.apple.Music")
        #expect(mixer.level(of: "com.spotify.client") == 0.5)
        let relaunched = Mixer(defaults: defaults, live: false)
        #expect(relaunched.level(of: "com.spotify.client") == 0.5 && relaunched.isMuted("com.apple.Music"))
        relaunched.setLevel(0.999, of: "com.spotify.client")
        #expect(!relaunched.isAdjusted("com.spotify.client"), "100% is the app's own volume")
        relaunched.reset("com.apple.Music")
        #expect(relaunched.levels.isEmpty && relaunched.muted.isEmpty)
    }
}

/// Renders the Sound tab with sample devices and apps at the default and the smallest open size.
/// With SNAPSHOT_DIR set, also writes PNGs there.
@MainActor
struct MixerSnapshotTests {
    private static let sizes = [("", CGSize(width: 428, height: 200)), ("-smallest", CGSize(width: 350, height: 102))]

    private static let outputs = [
        SoundDevice(id: 72, name: "MacBook Pro Speakers", symbol: "speaker.wave.2.fill"),
        SoundDevice(id: 80, name: "Niyam's AirPods Pro", symbol: "airpodspro"),
        SoundDevice(id: 91, name: "LG HDR 4K", symbol: "tv"),
    ]
    private static let inputs = [
        SoundDevice(id: 66, name: "MacBook Pro Microphone", symbol: "mic.fill"),
        SoundDevice(id: 80, name: "Niyam's AirPods Pro", symbol: "airpodspro"),
    ]

    private func sampleMixer() -> Mixer {
        let mixer = Mixer(defaults: UserDefaults(suiteName: "MixerSnapshot-\(UUID())")!, live: false)
        let apps = [
            ("com.spotify.client", "Spotify", "/Applications/Spotify.app", true),
            ("com.apple.Safari", "Safari", "/Applications/Safari.app", true),
            ("com.google.Chrome", "Google Chrome", "/Applications/Google Chrome.app", false),
            ("com.apple.Music", "Music", "/System/Applications/Music.app", false),
        ].map { id, name, path, playing in
            MixerApp(id: id, name: name, url: URL(filePath: path), isPlaying: playing)
        }
        mixer.setLevel(0.8, of: "com.spotify.client")
        mixer.setLevel(0.35, of: "com.apple.Safari")
        mixer.setLevel(0.6, of: "com.google.Chrome")
        mixer.toggleMute("com.apple.Music")
        let speakers = DeviceLevel(
            id: 72, name: "MacBook Pro Speakers", level: 0.56, isMuted: false, hasVolume: true, symbol: nil)
        let microphone = DeviceLevel(
            id: 66, name: "MacBook Pro Microphone", level: 0.7, isMuted: false, hasVolume: true, symbol: nil)
        mixer.preview(apps: apps, output: speakers, input: microphone, outputs: Self.outputs, inputs: Self.inputs)
        return mixer
    }

    @Test func theSoundTabWithAppsAndEmpty() throws {
        for (suffix, size) in Self.sizes {
            try render(SoundView(mixer: sampleMixer()), name: "sound" + suffix, size: size)
            let quiet = Mixer(defaults: UserDefaults(suiteName: "MixerSnapshot-\(UUID())")!, live: false)
            let airPods = DeviceLevel(
                id: 80, name: "Niyam's AirPods Pro", level: 0.3, isMuted: false, hasVolume: true, symbol: "airpodspro")
            let muted = DeviceLevel(
                id: 80, name: "Niyam's AirPods Pro", level: 0.5, isMuted: true, hasVolume: true, symbol: "airpodspro")
            quiet.preview(apps: [], output: airPods, input: muted, outputs: Self.outputs, inputs: Self.inputs)
            try render(SoundView(mixer: quiet), name: "sound-empty" + suffix, size: size)
        }
    }

    @Test func aDisplayWithoutAVolumeOfItsOwn() throws {
        let mixer = Mixer(defaults: UserDefaults(suiteName: "MixerSnapshot-\(UUID())")!, live: false)
        let display = DeviceLevel(id: 91, name: "LG HDR 4K", level: 1, isMuted: false, hasVolume: false, symbol: "tv")
        mixer.preview(apps: [], output: display, outputs: Self.outputs)
        try render(SoundView(mixer: mixer), name: "sound-display", size: Self.sizes[0].1)
    }

    /// Draws the view the way the notch shows a tab, white on black in dark mode, through AppKit,
    /// once the faders have risen into place (without animation, so at once).
    private func render(_ view: some View, name: String, size: CGSize) throws {
        let framed = view.frame(width: size.width, height: size.height).padding(16).background(.black)
            .foregroundStyle(.white).environment(\.colorScheme, .dark)
            .transaction { $0.animation = nil }
        let host = NSHostingView(rootView: framed)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: size.width + 32, height: size.height + 32), styleMask: .borderless,
            backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: .now + 0.1)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        #expect(bitmap.pixelsWide > 0)
        if let directory = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try bitmap.representation(using: .png, properties: [:])?.write(
                to: URL(filePath: directory).appending(path: "\(name).png"))
        }
    }
}
