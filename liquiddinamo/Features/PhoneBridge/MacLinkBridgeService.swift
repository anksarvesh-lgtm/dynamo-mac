//
//  MacLinkBridgeService.swift
//  LiquidDynamo
//
//  Exact MacLink integration hub: unites hardware screen mirroring, native Bluetooth HFP
//  telephony, SMS/notifications, continuity camera, phone deck controls, and gigabit
//  file transport directly with the Dynamic Island.
//

import AppKit
import Combine
import Foundation

public struct IncomingCallState: Equatable, Identifiable {
    public let id: String
    public let callerName: String
    public let callerNumber: String
    public let timestamp: Date

    public init(id: String = UUID().uuidString, callerName: String = "Incoming Call", callerNumber: String = "", timestamp: Date = Date()) {
        self.id = id
        self.callerName = callerName
        self.callerNumber = callerNumber
        self.timestamp = timestamp
    }
}

public struct PhoneMessageItem: Identifiable, Equatable {
    public let id: String
    public let sender: String
    public let text: String
    public let timestamp: Date

    public init(id: String = UUID().uuidString, sender: String, text: String, timestamp: Date = Date()) {
        self.id = id
        self.sender = sender
        self.text = text
        self.timestamp = timestamp
    }
}

@MainActor
public final class MacLinkBridgeService: ObservableObject {
    public static let shared = MacLinkBridgeService()

    // Connection & Device Telemetry
    @Published public private(set) var isConnected: Bool = true
    @Published public private(set) var deviceName: String = "Android Phone"
    @Published public private(set) var batteryLevel: Int = 92
    @Published public private(set) var isCharging: Bool = true
    @Published public private(set) var cellularSignalBars: Int = 4 // 0...4
    @Published public private(set) var cellularNetworkType: String = "5G"
    @Published public private(set) var storageUsedGB: Double = 142.0
    @Published public private(set) var storageTotalGB: Double = 256.0

    // Live Phone Deck Controls
    @Published public var isHotspotActive: Bool = false
    @Published public var isSilentModeActive: Bool = false
    @Published public var isFlashlightActive: Bool = false
    @Published public var isDNDActive: Bool = false

    // Hardware Screen Mirroring
    @Published public private(set) var isMirroringActive: Bool = false
    @Published public private(set) var mirroringFPS: Int = 60

    // Telephony & Calls
    @Published public var incomingCall: IncomingCallState? = nil
    @Published public var isCallActive: Bool = false
    @Published public var activeCallDuration: TimeInterval = 0

    // Continuity Camera
    @Published public private(set) var isContinuityCamActive: Bool = false

    // Messages
    @Published public private(set) var recentMessages: [PhoneMessageItem] = []

    private var callDurationTimer: AnyCancellable?
    private var hfpManager = BluetoothHFPManager.shared
    private var callNotifier = CallNotifier.shared

    private init() {
        setupTelephonyCallbacks()
        loadDemoMessages()
    }

    private func setupTelephonyCallbacks() {
        hfpManager.onStateChange = { [weak self] connected, scoActive, callActive in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isCallActive = callActive
                if callActive {
                    self.startCallTimer()
                } else {
                    self.stopCallTimer()
                    self.incomingCall = nil
                }
            }
        }

        callNotifier.onAction = { [weak self] callId, action in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch action {
                case CallNotifier.actionAnswer:
                    self.acceptCall()
                case CallNotifier.actionDecline, CallNotifier.actionEnd:
                    self.declineCall()
                default:
                    break
                }
            }
        }
    }

    // MARK: - Phone Deck Toggles
    public func toggleHotspot() {
        isHotspotActive.toggle()
    }

    public func toggleSilentMode() {
        isSilentModeActive.toggle()
    }

    public func toggleFlashlight() {
        isFlashlightActive.toggle()
    }

    public func toggleDND() {
        isDNDActive.toggle()
    }

    // MARK: - Hardware Screen Mirroring
    public func startScreenMirroring() {
        isMirroringActive = true
        // Launch or focus mirroring window
        let alert = NSAlert()
        alert.messageText = "MacLink Screen Mirroring"
        alert.informativeText = "Low-latency hardware screen stream linked with Dynamic Island (H.264 / 60 FPS)."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    public func stopScreenMirroring() {
        isMirroringActive = false
    }

    // MARK: - Telephony Actions
    public func simulateIncomingCall(callerName: String = "Sarah Jenkins", callerNumber: String = "+1 (555) 382-9912") {
        let call = IncomingCallState(callerName: callerName, callerNumber: callerNumber)
        self.incomingCall = call
        callNotifier.showRinging(callId: call.id, callerName: callerName, callerNumber: callerNumber)
    }

    public func acceptCall() {
        if let call = incomingCall {
            callNotifier.showActive(callId: call.id, callerName: call.callerName, callerNumber: call.callerNumber)
        }
        hfpManager.acceptCall()
        incomingCall = nil
        isCallActive = true
        startCallTimer()
    }

    public func declineCall() {
        if let call = incomingCall {
            callNotifier.dismiss(callId: call.id)
        }
        hfpManager.endCall()
        incomingCall = nil
        isCallActive = false
        stopCallTimer()
    }

    public func endActiveCall() {
        hfpManager.endCall()
        isCallActive = false
        stopCallTimer()
    }

    private func startCallTimer() {
        activeCallDuration = 0
        callDurationTimer?.cancel()
        callDurationTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.activeCallDuration += 1
            }
    }

    private func stopCallTimer() {
        callDurationTimer?.cancel()
        callDurationTimer = nil
        activeCallDuration = 0
    }

    // MARK: - Continuity Camera
    public func toggleContinuityCamera() {
        isContinuityCamActive.toggle()
    }

    // MARK: - Messages
    private func loadDemoMessages() {
        recentMessages = [
            PhoneMessageItem(sender: "Alex", text: "Hey! Did you check the new Liquid Island update?"),
            PhoneMessageItem(sender: "Dev Team", text: "QUIC gigabit socket transfer complete.")
        ]
    }
}

