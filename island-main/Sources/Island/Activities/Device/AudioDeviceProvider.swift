import CoreAudio
import Foundation
import IslandCore

/// Audio output route changes (AirPods / headphones / speakers) via CoreAudio property listeners.
/// Public API, no Bluetooth permission needed.
@MainActor
final class AudioDeviceProvider {
    private let sink: (ActivityUpdate) -> Void
    private let bus: EventBus
    private var listener: AudioObjectPropertyListenerBlock?
    private var lastDevice: AudioDeviceID?
    private var lastName: String?
    private var lastWasExternal = false
    /// AirPods connections are animated by `AirPodsConnectionAnimator` instead of the generic card.
    var onAirPodsConnected: ((String) -> Void)?
    var onAirPodsDisconnected: (() -> Void)?

    init(bus: EventBus, sink: @escaping (ActivityUpdate) -> Void) {
        self.bus = bus
        self.sink = sink
    }

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    func start() {
        guard listener == nil else { return }
        lastDevice = Self.defaultOutput()
        lastName = lastDevice.flatMap(Self.name)
        lastWasExternal = lastDevice.map { Self.transport($0) != kAudioDeviceTransportTypeBuiltIn } ?? false
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.changed() }
        }
        listener = block
        var addr = Self.defaultOutputAddress
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
    }

    func stop() {
        guard let listener else { return }
        var addr = Self.defaultOutputAddress
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, listener)
        self.listener = nil
    }

    private func changed() {
        guard let dev = Self.defaultOutput(), dev != lastDevice else { return }
        let name = Self.name(dev) ?? "Audio device"
        let transport = Self.transport(dev)
        let external = transport != kAudioDeviceTransportTypeBuiltIn
        defer { lastDevice = dev; lastName = name; lastWasExternal = external }
        let activity: DeviceActivity
        if external, name.lowercased().contains("airpods"), let onAirPodsConnected {
            onAirPodsConnected(name)
            return
        }
        if lastWasExternal, lastName?.lowercased().contains("airpods") == true { onAirPodsDisconnected?() }
        if external {
            activity = DeviceActivity(name: name, type: Self.type(name: name, transport: transport), connected: true)
            bus.publish(.deviceConnected(name: name))
        } else if lastWasExternal, let previous = lastName {
            activity = DeviceActivity(name: previous, type: .headphones, connected: false)
        } else {
            return
        }
        // Linger a little longer than the automatic presentation so the card never vanishes mid-animation.
        sink(.upsert(Activity(id: "device", kind: .device, priority: .high, content: .device(activity),
                              expiresAt: Date().addingTimeInterval(activity.connected ? 5 : 3))))
    }

    static func type(name: String, transport: UInt32) -> DeviceActivity.DeviceType {
        let lower = name.lowercased()
        if lower.contains("airpods") || lower.contains("headphone") || lower.contains("buds") || lower.contains("beats") { return .headphones }
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return .display
        case kAudioDeviceTransportTypeAirPlay: return .speaker
        default: return .other
        }
    }

    static func defaultOutput() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = defaultOutputAddress
        let err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return err == noErr && id != 0 ? id : nil
    }

    static func name(_ id: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) == noErr, let cf = name?.takeRetainedValue() else { return nil }
        return cf as String
    }

    static func transport(_ id: AudioDeviceID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var t: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &t)
        return t
    }
}
