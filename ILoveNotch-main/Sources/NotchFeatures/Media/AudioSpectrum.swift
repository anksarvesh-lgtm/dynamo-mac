// SPDX-License-Identifier: MIT
import Accelerate
import CoreAudio
import Foundation
import NotchCore
import Observation

/// How loud each band of frequencies in what's playing is, for the media waveform.
///
/// It listens to the Mac's audio output through a Core Audio process tap (macOS 14.2+). macOS asks
/// for permission to capture system audio the first time; if that's declined, the tap only hears
/// silence and the waveform keeps its own motion. Audio is analyzed as it plays and is never
/// recorded or stored, and MediaFeature only runs the tap while Media is on screen and playing.
@MainActor
@Observable
final class AudioSpectrum {
    /// Loudness per band, 0...1, lowest frequencies first. Empty while not listening.
    private(set) var bands: [Float] = []
    /// Whether the tap has heard anything lately. Constant silence while music plays usually
    /// means capture wasn't allowed.
    private(set) var isHearing = false

    @ObservationIgnored private var tap: SystemAudioTap?
    @ObservationIgnored private var lastSound = Date.distantPast
    @ObservationIgnored private var outputListener: AudioObjectPropertyListenerBlock?

    var isRunning: Bool { tap != nil }

    func start() {
        guard tap == nil else { return }
        let tap = SystemAudioTap { [weak self] bands in
            Task { @MainActor in self?.receive(bands) }
        }
        do {
            try tap.start()
        } catch {
            Log.features.error("Audio tap didn't start: \(String(describing: error), privacy: .public)")
            return
        }
        self.tap = tap
        listenForOutputChanges()
    }

    func stop() {
        stopListeningForOutputChanges()
        tap?.stop()
        tap = nil
        bands = []
        isHearing = false
    }

    private func receive(_ bands: [Float]) {
        guard tap != nil else { return }  // delivered just after stopping
        self.bands = bands
        let now = Date()
        if bands.contains(where: { $0 > 0.02 }) { lastSound = now }
        isHearing = now.timeIntervalSince(lastSound) < 2
    }

    /// The tap follows the output device it started on; switching to headphones restarts it.
    private func listenForOutputChanges() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.tap != nil else { return }
                self.stop()
                self.start()
            }
        }
        var address = SystemAudioTap.address(kAudioHardwarePropertyDefaultOutputDevice)
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener)
        if status == noErr { outputListener = listener }
    }

    private func stopListeningForOutputChanges() {
        guard let listener = outputListener else { return }
        var address = SystemAudioTap.address(kAudioHardwarePropertyDefaultOutputDevice)
        let system = AudioObjectID(kAudioObjectSystemObject)
        AudioObjectRemovePropertyListenerBlock(system, &address, DispatchQueue.main, listener)
        outputListener = nil
    }
}

/// Splits windows of mono audio into loudness per frequency band with Accelerate's FFT.
struct SpectrumAnalyzer {
    /// Samples per window: about 21 ms at 48 kHz.
    static let size = 1024

    /// Each band's range of FFT bins, log-spaced from 60 Hz to 14 kHz like hearing.
    let bins: [Range<Int>]
    /// dB added per band, rising 3 dB an octave from 1 kHz, so quieter treble still shows.
    private let tilt: [Float]
    private let window = vDSP.window(
        ofType: Float.self, usingSequence: .hanningDenormalized, count: Self.size, isHalfWindow: false)
    private let fft: vDSP.FFT<DSPSplitComplex>

    init?(sampleRate: Double, bands count: Int = 24) {
        let log2n = vDSP_Length(log2(Double(Self.size)))
        guard sampleRate > 0, count > 0,
            let fft = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self)
        else { return nil }
        self.fft = fft
        let binWidth = sampleRate / Double(Self.size)
        let low = 60.0
        let high = min(14_000, sampleRate / 2 * 0.95)
        func edge(_ band: Int) -> Double { low * pow(high / low, Double(band) / Double(count)) }
        bins = (0..<count).map { band in
            let first = max(1, Int(edge(band) / binWidth))
            let last = max(first + 1, Int((edge(band + 1) / binWidth).rounded(.up)))
            return first..<min(last, Self.size / 2)
        }
        tilt = (0..<count).map { band in Float(3 * log2(sqrt(edge(band) * edge(band + 1)) / 1000)) }
    }

    /// Loudness per band, 0...1, of one window of `size` mono samples: 0 at -60 dB or quieter, 1 at
    /// full scale.
    func bands(of samples: [Float]) -> [Float] {
        precondition(samples.count == Self.size)
        let half = Self.size / 2
        let windowed = vDSP.multiply(samples, window)
        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        var power = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { real in
            imaginary.withUnsafeMutableBufferPointer { imaginary in
                var split = DSPSplitComplex(realp: real.baseAddress!, imagp: imaginary.baseAddress!)
                windowed.withUnsafeBufferPointer { samples in
                    samples.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                fft.forward(input: split, output: &split)
                vDSP.squareMagnitudes(split, result: &power)
            }
        }
        // A full-scale sine through the Hann window peaks at (size / 2)² in vDSP's scaling.
        let fullScale = Float(half * half)
        return bins.indices.map { band in
            let range = bins[band]
            let mean = power[range].reduce(0, +) / Float(range.count)
            let decibels = 10 * log10(mean / fullScale + 1e-12) + tilt[band]
            return min(max((decibels + 60) / 60, 0), 1)
        }
    }
}

/// A Core Audio process tap on everything the Mac plays, through a private aggregate device on the
/// current output. Audio is mixed to mono and analyzed on the tap's queue; bands are delivered at
/// most 30 times a second. Its audio state is only touched on that queue.
private final class SystemAudioTap: @unchecked Sendable {
    struct Failure: Error, CustomStringConvertible {
        let step: String
        let status: OSStatus
        var description: String { "couldn't \(step) (\(status))" }
    }

    private let deliver: @Sendable ([Float]) -> Void
    private let queue = DispatchQueue(label: "cafe.opennotch.audio-tap", qos: .userInteractive)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    // Only touched on `queue`.
    private var analyzer: SpectrumAnalyzer?
    private var pending: [Float] = []
    private var levels: [Float] = []
    private var lastDelivery: UInt64 = 0

    init(deliver: @escaping @Sendable ([Float]) -> Void) {
        self.deliver = deliver
    }

    static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    func start() throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true
        description.name = "ILoveNotch waveform"
        try check("create the tap", AudioHardwareCreateProcessTap(description, &tapID))
        do {
            let format: AudioStreamBasicDescription = try read(tapID, kAudioTapPropertyFormat)
            let analyzer = SpectrumAnalyzer(sampleRate: format.mSampleRate)
            queue.sync { self.analyzer = analyzer }
            let system = AudioObjectID(kAudioObjectSystemObject)
            let output: AudioObjectID = try read(system, kAudioHardwarePropertyDefaultOutputDevice)
            let outputUID = try deviceUID(output)
            // The tap rides on the real output device; a tap alone as the main device hears nothing.
            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "ILoveNotch waveform",
                kAudioAggregateDeviceUIDKey: "cafe.opennotch.waveform.\(UUID().uuidString)",
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
                kAudioAggregateDeviceTapListKey: [
                    [kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]
                ],
            ]
            let created = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
            try check("create the aggregate device", created)
            try check(
                "add the IO proc",
                AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
                    self?.process(input)
                })
            try check("start the tap", AudioDeviceStart(aggregateID, procID))
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            queue.sync {}  // let an in-flight buffer finish before the device goes away
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    /// Mixes one buffer to mono, and analyzes each full window: bands rise at once and fall over
    /// about a fifth of a second.
    private func process(_ input: UnsafePointer<AudioBufferList>) {
        guard let analyzer else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, first.mDataByteSize > 0 else { return }
        if buffers.count == 1 {  // interleaved, or mono
            let channels = max(1, Int(first.mNumberChannels))
            let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * channels)
            guard let data = first.mData?.assumingMemoryBound(to: Float.self) else { return }
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<channels { sum += data[frame * channels + channel] }
                pending.append(sum / Float(channels))
            }
        } else {  // one buffer per channel
            let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            let channels = buffers.compactMap { $0.mData?.assumingMemoryBound(to: Float.self) }
            guard !channels.isEmpty else { return }
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in channels { sum += channel[frame] }
                pending.append(sum / Float(channels.count))
            }
        }
        let size = SpectrumAnalyzer.size
        guard pending.count >= size else { return }
        let fresh = analyzer.bands(of: Array(pending.suffix(size)))
        pending.removeAll(keepingCapacity: true)
        levels = levels.count == fresh.count ? zip(fresh, levels).map { max($0, $1 * 0.8) } : fresh
        let now = DispatchTime.now().uptimeNanoseconds
        if now - lastDelivery >= 33_000_000 {
            lastDelivery = now
            deliver(levels)
        }
    }

    private func check(_ step: String, _ status: OSStatus) throws {
        guard status == noErr else { throw Failure(step: step, status: status) }
    }

    private func read<Value>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> Value {
        var address = Self.address(selector)
        var size = UInt32(MemoryLayout<Value>.size)
        let value = UnsafeMutablePointer<Value>.allocate(capacity: 1)
        defer { value.deallocate() }
        try check("read property \(selector)", AudioObjectGetPropertyData(object, &address, 0, nil, &size, value))
        return value.move()
    }

    private func deviceUID(_ device: AudioObjectID) throws -> String {
        var address = Self.address(kAudioDevicePropertyDeviceUID)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var uid: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &uid) { uid in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, uid)
        }
        try check("read the output device", status)
        guard let uid else { throw Failure(step: "read the output device", status: kAudioHardwareUnspecifiedError) }
        return uid.takeRetainedValue() as String
    }
}
