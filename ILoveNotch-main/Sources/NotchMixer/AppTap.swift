// SPDX-License-Identifier: MIT
import Accelerate
import CoreAudio
import Foundation
import NotchCore

/// One app's sound at a volume of its own, the way macOS 14.2+ allows with public API: a Core
/// Audio process tap on the app's processes either mutes them (`silence`), or (`mix`) takes their
/// sound into a private aggregate device around the output they play on, whose IO proc plays it
/// back out at the app's gain. Started, the device waits for the app to play before its IO runs,
/// and `rearm()` puts it back to waiting once the app goes quiet, so a tap on a silent app costs
/// nothing and doesn't keep the output awake.
///
/// Reading a tap needs the "system audio recording" permission. Until some tap has heard sound,
/// a mixing tap leaves its app unmuted and plays silence, and only mutes the app at its source
/// once the tapped sound is known to arrive (`replace()`). So a denied permission leaves apps at
/// full volume rather than silent. Everything but `render` runs on the main actor.
final class AppTap: @unchecked Sendable {
    enum Mode: Hashable {
        /// Muted at the source; nothing to play back, so no IO at all.
        case silence
        /// Played back at the app's gain on this output device.
        case mix(device: AudioObjectID)
    }

    struct Failure: Error, CustomStringConvertible {
        let step: String
        let status: OSStatus
        var description: String { "couldn't \(step) (\(status))" }
    }

    let mode: Mode
    private(set) var processes: [AudioObjectID]

    /// The app's gain, 0...1. The IO proc ramps to a new value over one buffer, so drags don't click.
    var gain: Float {
        get { state.pointee.gain }
        set { state.pointee.gain = newValue.isFinite ? min(max(newValue, 0), 1) : 0 }
    }

    /// IO cycles run so far; zero a while after starting means the IO proc never ran.
    var cycles: UInt32 { state.pointee.cycles }

    private let name: String
    private let description: CATapDescription
    private let replacing: Bool
    private let heard: @MainActor @Sendable () -> Void
    private let state: UnsafeMutablePointer<RenderState>
    private let queue = DispatchQueue(label: "cafe.opennotch.mixer", qos: .userInteractive)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    /// Set if an IO proc couldn't be destroyed, so the audio thread may still use `state`.
    private var stateMayBeLive = false

    /// `replacing`: whether a tap has already heard sound this session, so the app can be muted
    /// at once. `heard` runs on the main actor the first time this tap carries sound.
    init(
        app: String, processes: [AudioObjectID], mode: Mode, gain: Float, replacing: Bool,
        heard: @escaping @MainActor @Sendable () -> Void
    ) {
        name = app
        self.processes = processes
        self.mode = mode
        self.replacing = replacing
        self.heard = heard
        state = .allocate(capacity: 1)
        state.initialize(to: RenderState())
        description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.isPrivate = true
        description.name = "ILoveNotch \(app)"
        description.muteBehavior =
            switch mode {
            case .silence: .muted
            case .mix: replacing ? .mutedWhenTapped : .unmuted
            }
        self.gain = gain
        state.pointee.applied = state.pointee.gain
    }

    deinit {
        stop()
        if !stateMayBeLive {
            state.deinitialize(count: 1)
            state.deallocate()
        }
    }

    func start() throws {
        do {
            try check("create the tap", AudioHardwareCreateProcessTap(description, &tapID))
            if case .mix(let device) = mode { try startMixing(on: device) }
        } catch {
            stop()
            throw error
        }
    }

    /// Mutes the app at its source now that its sound is known to reach the tap, and plays it at its
    /// gain instead. False if the tap wouldn't change, which calls for a new one.
    func replace() -> Bool {
        guard case .mix = mode, state.pointee.replacing == 0 else { return true }
        description.muteBehavior = .mutedWhenTapped
        guard describe() else { return false }
        state.pointee.replacing = 1
        return true
    }

    /// Follows the app's processes as helpers come and go, without stopping its sound. False if the
    /// tap wouldn't change, which calls for a new one.
    func retarget(_ processes: [AudioObjectID]) -> Bool {
        description.processes = processes
        guard describe() else { return false }
        self.processes = processes
        return true
    }

    /// Once the app goes quiet: stops the IO, which would otherwise keep running and the output device
    /// awake, and arms it again, so it waits for the app's next sound and starts from there.
    func rearm() {
        guard let procID else { return }
        AudioDeviceStop(aggregateID, procID)
        AudioDeviceStart(aggregateID, procID)
    }

    /// Hands the tap its changed description.
    private func describe() -> Bool {
        var address = AudioObjectID.address(kAudioTapPropertyDescription)
        var reference = description
        return withUnsafeMutablePointer(to: &reference) {
            AudioObjectSetPropertyData(tapID, &address, 0, nil, UInt32(MemoryLayout<CATapDescription>.size), $0)
        } == noErr
    }

    func stop() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            if AudioDeviceDestroyIOProcID(aggregateID, procID) != noErr { stateMayBeLive = true }
            queue.sync {}  // let a buffer in flight finish before the device goes away
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    private func startMixing(on device: AudioObjectID) throws {
        let format = tapID.read(kAudioTapPropertyFormat, default: AudioStreamBasicDescription())
        let channels = Int(format.mChannelsPerFrame)
        guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
            format.mBitsPerChannel == 32, channels > 0
        else { throw Failure(step: "read the tap's format", status: kAudioHardwareUnsupportedOperationError) }
        guard let deviceUID = device.readString(kAudioDevicePropertyDeviceUID) else {
            throw Failure(step: "read the output device", status: kAudioHardwareBadDeviceError)
        }
        // The tap rides on the real output device: its clock drives the IO proc, and what the IO proc
        // writes plays there. Only a tap listed at creation joins the aggregate.
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "ILoveNotch mixer",
            kAudioAggregateDeviceUIDKey: "cafe.opennotch.mixer.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: deviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: deviceUID]],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]
            ],
        ]
        try check(
            "create the aggregate device", AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID))
        let input = kAudioObjectPropertyScopeInput
        guard let aggregateInputs = aggregateID.bufferChannels(scope: input),
            let deviceInputs = device.bufferChannels(scope: input),
            let index = Self.tapBuffer(
                aggregate: aggregateInputs, device: deviceInputs, tapChannels: channels,
                terminals: { [aggregateID] in
                    aggregateID.readList(kAudioDevicePropertyStreams, scope: input).map { stream in
                        stream.has(kAudioStreamPropertyTerminalType)
                            ? stream.read(kAudioStreamPropertyTerminalType, default: UInt32(0)) : nil
                    }
                })
        else {
            throw Failure(
                step: "tell the tap from the device's own inputs", status: kAudioHardwareUnsupportedOperationError)
        }
        state.pointee.tapBuffer = Int32(index)
        state.pointee.tapChannels = UInt32(channels)
        state.pointee.replacing = replacing ? 1 : 0
        let shared = SharedState(pointer: state)
        let heard = heard
        try check(
            "add the IO proc",
            AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, input, _, output, _ in
                guard Self.render(input, into: output, state: shared.pointer) else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { heard() } }
            })
        try check("start the IO proc", AudioDeviceStart(aggregateID, procID))
        Log.mixer.debug(
            "Mixing \(self.name, privacy: .public) at \(format.mSampleRate, privacy: .public) Hz, tap is input \(index, privacy: .public) of \(aggregateInputs, privacy: .public)"
        )
    }

    private func check(_ step: String, _ status: OSStatus) throws {
        guard status == noErr else { throw Failure(step: step, status: status) }
    }

    /// Which of the aggregate's input buffers carries the tap. An aggregate lists its devices'
    /// streams first and its taps' after them (as the MIT-licensed per-app-audio observed), so with
    /// one device and one tap, the tap is the buffer after the device's own inputs. That's checked,
    /// never assumed: reading a device's input instead (an audio interface's line-in, say) would
    /// play it back out of its own speakers. When one of the device's inputs has as many channels as
    /// the tap, only a stream with no physical terminal type can be the tap. `terminals` gives each
    /// of the aggregate's input streams' terminal type, nil where unknown.
    static func tapBuffer(aggregate: [Int], device: [Int], tapChannels: Int, terminals: () -> [UInt32?]) -> Int? {
        guard tapChannels > 0, aggregate == device + [tapChannels] else { return nil }
        let index = device.count
        guard device.contains(tapChannels) else { return index }
        let types = terminals()
        guard types.count == aggregate.count else { return nil }
        return types.indices.filter { (types[$0] ?? 0) == 0 } == [index] ? index : nil
    }

    /// One IO cycle: the tapped sound at the app's gain, ramped over the buffer from the last
    /// cycle's gain, onto the output's channels (left and right on the first two, both on a mono
    /// device, silence on the rest). Silence until the app is muted at its source. Returns true
    /// for the first cycle that carries sound. Runs on the audio thread: no allocation, no locks,
    /// no `self`.
    static func render(
        _ input: UnsafePointer<AudioBufferList>, into output: UnsafeMutablePointer<AudioBufferList>,
        state: UnsafeMutablePointer<RenderState>
    ) -> Bool {
        state.pointee.cycles &+= 1
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        let index = Int(state.pointee.tapBuffer)
        let channels = Int(state.pointee.tapChannels)
        guard index >= 0, index < inputs.count, channels > 0, inputs[index].mNumberChannels == UInt32(channels),
            let data = inputs[index].mData
        else {
            silence(outputs)
            return false
        }
        let source = UnsafePointer(data.assumingMemoryBound(to: Float.self))
        let frames = Int(inputs[index].mDataByteSize) / (MemoryLayout<Float>.size * channels)
        var first = false
        if state.pointee.heard == 0, frames > 0 {
            var peak: Float = 0
            vDSP_maxmgv(source, 1, &peak, vDSP_Length(frames * channels))
            if peak > 0 {
                state.pointee.heard = 1
                first = true
            }
        }
        guard state.pointee.replacing != 0 else {
            silence(outputs)
            return first
        }
        let start = state.pointee.applied
        let end = state.pointee.gain
        state.pointee.applied = end
        let step = frames > 0 ? (end - start) / Float(frames) : 0
        var total = 0
        for buffer in outputs { total += Int(buffer.mNumberChannels) }
        let mono = total == 1 && channels > 1
        var channel = 0  // the first channel of this output buffer, counted across buffers
        for buffer in outputs {
            let count = Int(buffer.mNumberChannels)
            defer { channel += count }
            guard count > 0, let data = buffer.mData else { continue }
            let target = data.assumingMemoryBound(to: Float.self)
            let length = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * count)
            for local in 0..<count {
                let from = channels == 1 ? 0 : channel + local
                for frame in 0..<length {
                    var sample: Float = 0
                    if frame < frames {
                        if mono {
                            for c in 0..<channels { sample += source[frame * channels + c] }
                            sample /= Float(channels)
                        } else if from < channels {
                            sample = source[frame * channels + from]
                        }
                        sample *= start + step * Float(frame)
                    }
                    target[frame * count + local] = sample.isFinite ? min(max(sample, -1), 1) : 0
                }
            }
        }
        return first
    }

    private static func silence(_ buffers: UnsafeMutableAudioBufferListPointer) {
        for buffer in buffers where buffer.mData != nil { memset(buffer.mData, 0, Int(buffer.mDataByteSize)) }
    }
}

/// What the IO proc and the main actor share, in one allocation the IO block reaches through a
/// pointer: no locks and no reference counting on the audio thread. Each field is one word, so
/// either side sees the old value or the new one, never a mix.
struct RenderState {
    /// The app's gain, 0...1, set from the main actor.
    var gain: Float = 1
    /// The gain the last buffer ended on; the next one ramps from it.
    var applied: Float = 1
    /// Which input buffer is the tap's, and its channels.
    var tapBuffer: Int32 = -1
    var tapChannels: UInt32 = 0
    /// 1 once the app is muted at its source, so this is its only sound. Until then the IO proc
    /// writes silence, so the app never plays twice.
    var replacing: UInt32 = 0
    /// 1 once the tap has delivered sound: macOS lets ILoveNotch hear the app.
    var heard: UInt32 = 0
    var cycles: UInt32 = 0
}

/// The render state's address, for the IO block to carry to the audio thread.
private struct SharedState: @unchecked Sendable {
    let pointer: UnsafeMutablePointer<RenderState>
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(
        _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    func has(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> Bool
    {
        var address = Self.address(selector, scope)
        return AudioObjectHasProperty(self, &address)
    }

    /// A property's value, or `fallback` when the object can't give it.
    func read<Value>(
        _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        default fallback: Value
    ) -> Value {
        var address = Self.address(selector, scope)
        var size = UInt32(MemoryLayout<Value>.size)
        var value = fallback
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, $0)
        }
        return status == noErr ? value : fallback
    }

    @discardableResult
    func write<Value>(
        _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        _ value: Value
    ) -> Bool {
        var address = Self.address(selector, scope)
        var value = value
        let size = UInt32(MemoryLayout<Value>.size)
        return withUnsafeMutablePointer(to: &value) { AudioObjectSetPropertyData(self, &address, 0, nil, size, $0) }
            == noErr
    }

    func readString(
        _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> String? {
        var address = Self.address(selector, scope)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var text: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &text) {
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let text else { return nil }
        return text.takeRetainedValue() as String
    }

    /// A list of objects, such as the processes that use audio or a device's streams.
    func readList(
        _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> [AudioObjectID] {
        var address = Self.address(selector, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var list = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(self, &address, 0, nil, &size, &list) == noErr else { return [] }
        return Array(list.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    /// Channels per buffer of a device's input or output, in the order its IO proc gets them.
    func bufferChannels(scope: AudioObjectPropertyScope) -> [Int]? {
        var address = Self.address(kAudioDevicePropertyStreamConfiguration, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size) == noErr else { return nil }
        let bytes = Swift.max(Int(size), MemoryLayout<AudioBufferList>.size)
        let raw = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(self, &address, 0, nil, &size, raw) == noErr else { return nil }
        return UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
            .map { Int($0.mNumberChannels) }
    }
}

/// Calls back on the main queue whenever a Core Audio property changes, until cancelled.
@MainActor
final class PropertyListener {
    private let object: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock

    init?(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        changed: @escaping @MainActor @Sendable () -> Void
    ) {
        self.object = object
        address = AudioObjectID.address(selector, scope)
        block = { _, _ in MainActor.assumeIsolated { changed() } }
        guard AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr else { return nil }
    }

    func cancel() {
        AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
    }
}
