// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import IOBluetooth

/**
 * Manages Bluetooth Hands-Free Profile (HFP v1.7) connection between Mac (HF role)
 * and paired Android phone (AG role).
 *
 * Capabilities:
 * - Establishes Service Level Connection (SLC) over RFCOMM.
 * - Manages Synchronous Connection-Oriented (SCO / eSCO) audio links for calls.
 * - Routes voice audio between Mac microphone/speaker and the cellular call.
 * - Dispatches telephony AT commands (ATA, AT+CHUP, ATD).
 */
public final class BluetoothHFPManager: NSObject, IOBluetoothHandsFreeDeviceDelegate {
    public static let shared = BluetoothHFPManager()

    public typealias StateChangeHandler = (_ connected: Bool, _ scoActive: Bool, _ callActive: Bool) -> Void
    public var onStateChange: StateChangeHandler?

    private var hfDevice: IOBluetoothHandsFreeDevice?
    private var targetDevice: IOBluetoothDevice?

    public private(set) var isConnected: Bool = false
    public private(set) var isScoActive: Bool = false
    public private(set) var isCallActive: Bool = false

    private override init() {
        super.init()
    }

    /**
     * Connects to a paired Bluetooth phone by MAC address (e.g. "AA:BB:CC:DD:EE:FF" or "aabb-ccdd-eeff").
     */
    public func connect(deviceAddress: String) -> Bool {
        let normalized = deviceAddress
            .replacingOccurrences(of: ":", with: "-")
            .lowercased()

        guard let device = IOBluetoothDevice(addressString: normalized) else {
            return false
        }

        disconnect()
        self.targetDevice = device

        let features: uint32 =
            IOBluetoothHandsFreeDeviceFeatures.ecAndOrNRFunction.rawValue |
            IOBluetoothHandsFreeDeviceFeatures.threeWayCalling.rawValue |
            IOBluetoothHandsFreeDeviceFeatures.cliPresentation.rawValue |
            IOBluetoothHandsFreeDeviceFeatures.remoteVolumeControl.rawValue |
            IOBluetoothHandsFreeDeviceFeatures.enhancedCallStatus.rawValue |
            IOBluetoothHandsFreeDeviceFeatures.codecNegotiation.rawValue

        guard let hf = IOBluetoothHandsFreeDevice(device: device, delegate: self) else {
            return false
        }

        hf.supportedFeatures = features
        self.hfDevice = hf
        hf.connect()
        return true
    }

    /**
     * Disconnects active HFP and SCO audio connections.
     */
    public func disconnect() {
        if let hf = hfDevice {
            if hf.isSCOConnected() {
                hf.disconnectSCO()
            }
            if hf.isConnected {
                hf.disconnect()
            }
        }
        hfDevice = nil
        targetDevice = nil
        updateState(connected: false, sco: false, call: false)
    }

    /**
     * Answers an incoming cellular call and transfers voice audio to the Mac.
     */
    public func acceptCall() {
        guard let hf = hfDevice, isConnected else { return }
        hf.acceptCall()
        routeAudioToMac()
    }

    /**
     * Hangs up an active call or declines an incoming call.
     */
    public func endCall() {
        guard let hf = hfDevice, isConnected else { return }
        hf.endCall()
        routeAudioToPhone()
    }

    /**
     * Dials an outgoing phone number through the connected phone.
     */
    public func dial(number: String) {
        guard let hf = hfDevice, isConnected else { return }
        let clean = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        hf.dialNumber(clean)
        routeAudioToMac()
    }

    /**
     * Opens the SCO voice audio link and transfers voice to the Mac.
     */
    public func routeAudioToMac() {
        guard let hf = hfDevice, isConnected else { return }
        if !hf.isSCOConnected() {
            hf.connectSCO()
        }
        hf.transferAudioToComputer()
    }

    /**
     * Closes the SCO voice audio link and returns voice to the phone earpiece/speaker.
     */
    public func routeAudioToPhone() {
        guard let hf = hfDevice, isConnected else { return }
        hf.transferAudioToPhone()
        if hf.isSCOConnected() {
            hf.disconnectSCO()
        }
    }

    private func updateState(connected: Bool? = nil, sco: Bool? = nil, call: Bool? = nil) {
        if let c = connected { isConnected = c }
        if let s = sco { isScoActive = s }
        if let cl = call { isCallActive = cl }
        onStateChange?(isConnected, isScoActive, isCallActive)
    }

    // MARK: - IOBluetoothHandsFreeDelegate

    public func handsFree(_ device: IOBluetoothHandsFree!, connected status: NSNumber!) {
        let ok = status?.int32Value == kIOReturnSuccess
        updateState(connected: ok)
    }

    public func handsFree(_ device: IOBluetoothHandsFree!, disconnected status: NSNumber!) {
        updateState(connected: false, sco: false, call: false)
    }

    public func handsFree(_ device: IOBluetoothHandsFree!, scoConnectionOpened status: NSNumber!) {
        let ok = status?.int32Value == kIOReturnSuccess
        updateState(sco: ok)
    }

    public func handsFree(_ device: IOBluetoothHandsFree!, scoConnectionClosed status: NSNumber!) {
        updateState(sco: false)
    }

    // MARK: - IOBluetoothHandsFreeDeviceDelegate

    public func handsFree(_ device: IOBluetoothHandsFreeDevice!, isCallActive: NSNumber!) {
        let active = isCallActive?.intValue != 0
        updateState(call: active)
    }

    public func handsFree(_ device: IOBluetoothHandsFreeDevice!, callSetupMode: NSNumber!) {
        // Mode 1: incoming, 2: outgoing, 3: alerting
        let mode = callSetupMode?.intValue ?? 0
        if mode != 0 {
            updateState(call: true)
        }
    }
}
