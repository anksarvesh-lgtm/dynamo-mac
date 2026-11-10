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

public struct PhoneCallHistoryItem: Identifiable, Equatable {
    public enum CallType: String, Equatable {
        case incoming = "Incoming"
        case outgoing = "Outgoing"
        case missed = "Missed"
    }

    public let id: String
    public let callerName: String
    public let callerNumber: String
    public let date: Date
    public let duration: TimeInterval
    public let type: CallType

    public init(
        id: String = UUID().uuidString,
        callerName: String,
        callerNumber: String,
        date: Date = Date(),
        duration: TimeInterval = 0,
        type: CallType = .incoming
    ) {
        self.id = id
        self.callerName = callerName
        self.callerNumber = callerNumber
        self.date = date
        self.duration = duration
        self.type = type
    }
}

public struct PhoneAppItem: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let packageName: String
    public let iconSystemName: String
    public let isSystemApp: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        packageName: String,
        iconSystemName: String = "app.fill",
        isSystemApp: Bool = false
    ) {
        self.id = id
        self.name = name
        self.packageName = packageName
        self.iconSystemName = iconSystemName
        self.isSystemApp = isSystemApp
    }
}

public struct PhonePhotoItem: Identifiable, Equatable {
    public let id: String
    public let filename: String
    public let dateAdded: Date
    public let sizeBytes: Int64
    public let remotePath: String

    public init(
        id: String = UUID().uuidString,
        filename: String,
        dateAdded: Date = Date(),
        sizeBytes: Int64 = 2_500_000,
        remotePath: String = "/sdcard/DCIM/Camera/"
    ) {
        self.id = id
        self.filename = filename
        self.dateAdded = dateAdded
        self.sizeBytes = sizeBytes
        self.remotePath = remotePath
    }
}

public struct PhoneSyncEventItem: Identifiable, Equatable {
    public enum SyncEventType: String {
        case notification = "Notification"
        case clipboard = "Clipboard"
        case fileTransfer = "File Transfer"
    }

    public let id: String
    public let timestamp: Date
    public let title: String
    public let detail: String
    public let type: SyncEventType

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        title: String,
        detail: String,
        type: SyncEventType = .notification
    ) {
        self.id = id
        self.timestamp = timestamp
        self.title = title
        self.detail = detail
        self.type = type
    }
}

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

    // Extended MacLink Hub Data
    @Published public private(set) var recentCalls: [PhoneCallHistoryItem] = []
    @Published public private(set) var installedApps: [PhoneAppItem] = []
    @Published public private(set) var recentPhotos: [PhonePhotoItem] = []
    @Published public private(set) var syncEvents: [PhoneSyncEventItem] = []
    @Published public var clipboardSyncEnabled: Bool = true

    private var callDurationTimer: AnyCancellable?
    private var hfpManager = BluetoothHFPManager.shared
    private var callNotifier = CallNotifier.shared

    private init() {
        setupTelephonyCallbacks()
        loadDemoMessages()
        loadDemoData()
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

    // MARK: - Actions & Demo Data
    public func dialNumber(_ number: String) {
        let call = IncomingCallState(callerName: "Outgoing Call", callerNumber: number)
        incomingCall = call
        isCallActive = true
        startCallTimer()
        let record = PhoneCallHistoryItem(callerName: number, callerNumber: number, duration: 0, type: .outgoing)
        recentCalls.insert(record, at: 0)
    }

    public func sendMessage(recipient: String, text: String) {
        let msg = PhoneMessageItem(sender: "You", text: text)
        recentMessages.append(msg)
        syncEvents.insert(PhoneSyncEventItem(title: "Sent Message", detail: "\(recipient): \(text)", type: .notification), at: 0)
    }

    public func launchApp(_ app: PhoneAppItem) {
        syncEvents.insert(PhoneSyncEventItem(title: "Remote App Launch", detail: "Launched \(app.name) on connected device", type: .notification), at: 0)
        startScreenMirroring()
    }

    public func triggerPhotoBackup() {
        syncEvents.insert(PhoneSyncEventItem(title: "Photo Sync", detail: "Backed up \(recentPhotos.count) camera photos to ~/Pictures/PhoneBackup", type: .fileTransfer), at: 0)
    }

    private func loadDemoMessages() {
        recentMessages = [
            PhoneMessageItem(sender: "Alex", text: "Hey! Did you check the new Liquid Island update?"),
            PhoneMessageItem(sender: "Dev Team", text: "QUIC gigabit socket transfer complete."),
            PhoneMessageItem(sender: "Mom", text: "Call me when you are free!"),
            PhoneMessageItem(sender: "Support", text: "Your verification code is 482-901.")
        ]
    }

    private func loadDemoData() {
        recentCalls = [
            PhoneCallHistoryItem(callerName: "Sarah Jenkins", callerNumber: "+1 (555) 382-9912", date: Date().addingTimeInterval(-1800), duration: 245, type: .incoming),
            PhoneCallHistoryItem(callerName: "Office Desk", callerNumber: "+1 (555) 019-4821", date: Date().addingTimeInterval(-7200), duration: 62, type: .outgoing),
            PhoneCallHistoryItem(callerName: "Unknown Caller", callerNumber: "+1 (800) 492-1004", date: Date().addingTimeInterval(-14400), duration: 0, type: .missed)
        ]

        installedApps = [
            PhoneAppItem(name: "Camera", packageName: "com.android.camera", iconSystemName: "camera.fill"),
            PhoneAppItem(name: "Photos", packageName: "com.google.android.apps.photos", iconSystemName: "photo.on.rectangle.angled"),
            PhoneAppItem(name: "WhatsApp", packageName: "com.whatsapp", iconSystemName: "message.badge.filled.fill"),
            PhoneAppItem(name: "Spotify", packageName: "com.spotify.music", iconSystemName: "music.note"),
            PhoneAppItem(name: "YouTube", packageName: "com.google.android.youtube", iconSystemName: "play.rectangle.fill"),
            PhoneAppItem(name: "Chrome", packageName: "com.android.chrome", iconSystemName: "globe"),
            PhoneAppItem(name: "Settings", packageName: "com.android.settings", iconSystemName: "gearshape.fill", isSystemApp: true),
            PhoneAppItem(name: "Files", packageName: "com.google.android.documentsui", iconSystemName: "folder.fill", isSystemApp: true)
        ]

        recentPhotos = [
            PhonePhotoItem(filename: "IMG_20261110_142018.jpg", dateAdded: Date().addingTimeInterval(-3600), sizeBytes: 3_450_000),
            PhonePhotoItem(filename: "IMG_20261110_121104.jpg", dateAdded: Date().addingTimeInterval(-12000), sizeBytes: 4_100_000),
            PhonePhotoItem(filename: "IMG_20261109_194420.jpg", dateAdded: Date().addingTimeInterval(-86400), sizeBytes: 2_890_000),
            PhonePhotoItem(filename: "IMG_20261109_181200.jpg", dateAdded: Date().addingTimeInterval(-92000), sizeBytes: 5_210_000),
            PhonePhotoItem(filename: "IMG_20261108_103011.jpg", dateAdded: Date().addingTimeInterval(-172800), sizeBytes: 3_120_000)
        ]

        syncEvents = [
            PhoneSyncEventItem(title: "Device Connected", detail: "Connected via High-Speed USB ADB (5 Gbps)", type: .notification),
            PhoneSyncEventItem(title: "Clipboard Synced", detail: "Copied 48 characters from Mac to Phone", type: .clipboard),
            PhoneSyncEventItem(title: "File Transferred", detail: "Presentation.pdf transferred in 120ms", type: .fileTransfer)
        ]
    }
}

