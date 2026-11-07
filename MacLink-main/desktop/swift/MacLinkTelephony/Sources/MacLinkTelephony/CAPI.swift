// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public typealias CCallActionCallback = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> Void

private var globalActionCallback: CCallActionCallback?

@_cdecl("maclink_calls_init")
public func maclink_calls_init() {
    _ = CallNotifier.shared
}

@_cdecl("maclink_calls_register_action_callback")
public func maclink_calls_register_action_callback(callback: CCallActionCallback?) {
    globalActionCallback = callback
    CallNotifier.shared.onAction = { callId, action in
        callId.withCString { cCallId in
            action.withCString { cAction in
                globalActionCallback?(cCallId, cAction)
            }
        }
    }
}

@_cdecl("maclink_calls_notify_ringing")
public func maclink_calls_notify_ringing(
    callId: UnsafePointer<CChar>?,
    callerName: UnsafePointer<CChar>?,
    callerNumber: UnsafePointer<CChar>?
) {
    guard let callId = callId.flatMap({ String(validatingUTF8: $0) }) else { return }
    let name = callerName.flatMap { String(validatingUTF8: $0) }
    let number = callerNumber.flatMap { String(validatingUTF8: $0) }
    CallNotifier.shared.showRinging(callId: callId, callerName: name, callerNumber: number)
}

@_cdecl("maclink_calls_notify_active")
public func maclink_calls_notify_active(
    callId: UnsafePointer<CChar>?,
    callerName: UnsafePointer<CChar>?,
    callerNumber: UnsafePointer<CChar>?
) {
    guard let callId = callId.flatMap({ String(validatingUTF8: $0) }) else { return }
    let name = callerName.flatMap { String(validatingUTF8: $0) }
    let number = callerNumber.flatMap { String(validatingUTF8: $0) }
    CallNotifier.shared.showActive(callId: callId, callerName: name, callerNumber: number)
}

@_cdecl("maclink_calls_dismiss")
public func maclink_calls_dismiss(callId: UnsafePointer<CChar>?) {
    guard let callId = callId.flatMap({ String(validatingUTF8: $0) }) else { return }
    CallNotifier.shared.dismiss(callId: callId)
}

@_cdecl("maclink_calls_hfp_publish_sdp")
public func maclink_calls_hfp_publish_sdp(rfcommChannel: UInt8) -> Bool {
    return HfpServiceRecord.shared.publish(rfcommChannel: rfcommChannel)
}

@_cdecl("maclink_calls_hfp_unpublish_sdp")
public func maclink_calls_hfp_unpublish_sdp() {
    HfpServiceRecord.shared.unpublish()
}

@_cdecl("maclink_calls_hfp_connect")
public func maclink_calls_hfp_connect(deviceAddress: UnsafePointer<CChar>?) -> Bool {
    guard let addr = deviceAddress.flatMap({ String(validatingUTF8: $0) }) else { return false }
    return BluetoothHFPManager.shared.connect(deviceAddress: addr)
}

@_cdecl("maclink_calls_hfp_disconnect")
public func maclink_calls_hfp_disconnect() {
    BluetoothHFPManager.shared.disconnect()
}

@_cdecl("maclink_calls_hfp_is_connected")
public func maclink_calls_hfp_is_connected() -> Bool {
    return BluetoothHFPManager.shared.isConnected
}

@_cdecl("maclink_calls_hfp_is_sco_active")
public func maclink_calls_hfp_is_sco_active() -> Bool {
    return BluetoothHFPManager.shared.isScoActive
}

@_cdecl("maclink_calls_hfp_route_audio")
public func maclink_calls_hfp_route_audio(toMac: Bool) {
    if toMac {
        BluetoothHFPManager.shared.routeAudioToMac()
    } else {
        BluetoothHFPManager.shared.routeAudioToPhone()
    }
}

@_cdecl("maclink_calls_hfp_accept")
public func maclink_calls_hfp_accept() {
    BluetoothHFPManager.shared.acceptCall()
}

@_cdecl("maclink_calls_hfp_end")
public func maclink_calls_hfp_end() {
    BluetoothHFPManager.shared.endCall()
}

@_cdecl("maclink_calls_hfp_dial")
public func maclink_calls_hfp_dial(number: UnsafePointer<CChar>?) -> Bool {
    guard let num = number.flatMap({ String(validatingUTF8: $0) }) else { return false }
    BluetoothHFPManager.shared.dial(number: num)
    return true
}

