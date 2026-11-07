import CoreAudio
import CoreMediaIO
import Foundation
import IslandCore

/// "Recording" = microphone and/or camera in use by any app, detected with the public
/// `…DeviceIsRunningSomewhere` properties (CoreAudio / CoreMediaIO) and property listeners.
/// Island cannot stop another app's capture, so it offers no stop button.
@MainActor
final class RecordingProvider {
    private let sink: (ActivityUpdate) -> Void
    private var audioListeners: [(AudioObjectID, AudioObjectPropertyListenerBlock)] = []
    private var cameraListeners: [(CMIOObjectID, CMIOObjectPropertyListenerBlock)] = []
    private var deviceListListener: AudioObjectPropertyListenerBlock?
    private var startedAt: Date?
    private(set) var micActive = false
    private(set) var cameraActive = false

    init(sink: @escaping (ActivityUpdate) -> Void) { self.sink = sink }

    private static var devicesAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    private static var runningAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    func start() {
        guard deviceListListener == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in DispatchQueue.main.async { self?.rebuild() } }
        deviceListListener = block
        var addr = Self.devicesAddress
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
        rebuild()
    }

    func stop() {
        removeDeviceListeners()
        if let l = deviceListListener {
            var addr = Self.devicesAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, l)
        }
        deviceListListener = nil
    }

    private func removeDeviceListeners() {
        for (id, l) in audioListeners {
            var addr = Self.runningAddress
            AudioObjectRemovePropertyListenerBlock(id, &addr, DispatchQueue.main, l)
        }
        audioListeners.removeAll()
        for (id, l) in cameraListeners {
            var addr = Self.cmioRunningAddress
            CMIOObjectRemovePropertyListenerBlock(id, &addr, DispatchQueue.main, l)
        }
        cameraListeners.removeAll()
    }

    private func rebuild() {
        removeDeviceListeners()
        for id in Self.inputDevices() {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in DispatchQueue.main.async { self?.evaluate() } }
            var addr = Self.runningAddress
            if AudioObjectAddPropertyListenerBlock(id, &addr, DispatchQueue.main, block) == noErr { audioListeners.append((id, block)) }
        }
        for id in Self.cameraDevices() {
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in DispatchQueue.main.async { self?.evaluate() } }
            var addr = Self.cmioRunningAddress
            if CMIOObjectAddPropertyListenerBlock(id, &addr, DispatchQueue.main, block) == noErr { cameraListeners.append((id, block)) }
        }
        evaluate()
    }

    private func evaluate() {
        let mic = audioListeners.contains { Self.isRunning($0.0) }
        let cam = cameraListeners.contains { Self.cameraRunning($0.0) }
        guard mic != micActive || cam != cameraActive || (startedAt == nil && (mic || cam)) else { return }
        micActive = mic
        cameraActive = cam
        if mic || cam {
            let start = startedAt ?? Date()
            startedAt = start
            sink(.upsert(Activity(id: "recording", kind: .recording, priority: .normal,
                                  content: .recording(RecordingActivity(microphone: mic, camera: cam, startedAt: start)))))
        } else {
            startedAt = nil
            sink(.remove(id: "recording"))
        }
    }

    // MARK: CoreAudio

    static func inputDevices() -> [AudioObjectID] {
        var addr = devicesAddress
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter(hasInput)
    }

    static func hasInput(_ id: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }

    static func isRunning(_ id: AudioObjectID) -> Bool {
        var addr = runningAddress
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &v) == noErr && v != 0
    }

    // MARK: CoreMediaIO

    static var cmioRunningAddress = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal), mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))

    static func cameraDevices() -> [CMIOObjectID] {
        var addr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                             mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                             mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &ids) == noErr else { return [] }
        return ids
    }

    static func cameraRunning(_ id: CMIOObjectID) -> Bool {
        var addr = cmioRunningAddress
        var v: UInt32 = 0
        var used: UInt32 = 0
        return CMIOObjectGetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &v) == noErr && v != 0
    }
}
