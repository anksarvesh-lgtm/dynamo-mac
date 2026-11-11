// SPDX-License-Identifier: MIT
import AppKit
import Combine
import Foundation
import IOKit.pwr_mgt

@MainActor
public final class KeepAwakeManager: ObservableObject {
    public static let shared = KeepAwakeManager()

    // MARK: - Published State

    @Published public private(set) var isActive: Bool = false
    @Published public var mode: KeepAwakeMode = .displayAndSystem {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Keys.lastMode)
        }
    }
    @Published public private(set) var activeDuration: KeepAwakeDuration = .preset(.h1)
    @Published public private(set) var isIndefinite: Bool = false
    @Published public private(set) var startDate: Date? = nil
    @Published public private(set) var endDate: Date? = nil
    @Published public private(set) var totalDurationSeconds: TimeInterval = 0
    @Published public private(set) var remainingSeconds: TimeInterval = 0
    @Published public private(set) var remainingFormatted: String = ""
    @Published public private(set) var progress: Double = 0.0
    @Published public private(set) var lastErrorMessage: String? = nil

    public static let clamshellNote: String =
        "Note: Closed-display mode requires your Mac laptop to be connected to AC power and an external display. macOS does not permit battery-only closed operation."

    // MARK: - Dependencies & Private State

    private let assertionProvider: PowerAssertionProviding
    private var currentAssertionID: IOPMAssertionID = 0
    private var tickerTimer: Timer?
    private var notificationTokens: [NSObjectProtocol] = []

    // MARK: - Persistence Keys

    private enum Keys {
        static let lastMode = "maclink.keepAwake.lastMode"
        static let lastPreset = "maclink.keepAwake.lastPreset"
        static let activeEndDate = "maclink.keepAwake.activeEndDate"
        static let activeTotalDuration = "maclink.keepAwake.activeTotalDuration"
        static let activeIsIndefinite = "maclink.keepAwake.activeIsIndefinite"
        static let activeMode = "maclink.keepAwake.activeMode"
    }

    // MARK: - Initializer

    public init(assertionProvider: PowerAssertionProviding = IOKitPowerAssertionProvider()) {
        self.assertionProvider = assertionProvider

        if let savedModeRaw = UserDefaults.standard.string(forKey: Keys.lastMode),
           let savedMode = KeepAwakeMode(rawValue: savedModeRaw) {
            self.mode = savedMode
        }

        setupSystemObservers()
        restoreSessionIfPersisted()
    }

    deinit {
        if currentAssertionID != 0 {
            _ = assertionProvider.releaseAssertion(id: currentAssertionID)
        }
    }

    // MARK: - Public Control API

    @discardableResult
    public func start(mode: KeepAwakeMode, duration: KeepAwakeDuration) -> Bool {
        releaseCurrentAssertion()

        self.mode = mode
        self.activeDuration = duration
        self.lastErrorMessage = nil

        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "MacLink"
        let reason = "\(appName): Keep Awake active" as CFString

        let (newID, result) = assertionProvider.createAssertion(
            type: mode.assertionType,
            level: IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name: reason
        )

        guard result == kIOReturnSuccess, newID != 0 else {
            self.isActive = false
            self.lastErrorMessage = "Failed to acquire power assertion (code \(result))."
            clearPersistentState()
            return false
        }

        self.currentAssertionID = newID
        self.isActive = true
        self.startDate = Date()

        if duration.isIndefinite {
            self.isIndefinite = true
            self.endDate = nil
            self.totalDurationSeconds = 0
            self.remainingSeconds = 0
            self.remainingFormatted = "Indefinite"
            self.progress = 1.0
        } else if let seconds = duration.durationSeconds {
            self.isIndefinite = false
            self.totalDurationSeconds = seconds
            self.endDate = Date().addingTimeInterval(seconds)
            updateRemainingTime()
        }

        persistActiveSession()
        startTickerTimer()
        return true
    }

    public func stop() {
        releaseCurrentAssertion()
        stopTickerTimer()

        self.isActive = false
        self.isIndefinite = false
        self.startDate = nil
        self.endDate = nil
        self.totalDurationSeconds = 0
        self.remainingSeconds = 0
        self.remainingFormatted = ""
        self.progress = 0.0

        clearPersistentState()
    }

    public func toggle(defaultPreset: KeepAwakePreset = .h1) {
        if isActive {
            stop()
        } else {
            let lastPresetRaw = UserDefaults.standard.string(forKey: Keys.lastPreset) ?? defaultPreset.rawValue
            let preset = KeepAwakePreset(rawValue: lastPresetRaw) ?? defaultPreset
            start(mode: self.mode, duration: .preset(preset))
        }
    }

    public func extend(by seconds: TimeInterval = 15 * 60) {
        guard isActive else { return }
        guard !isIndefinite else { return }

        let currentRemaining = remainingSeconds
        let newRemaining = currentRemaining + seconds
        let newEndDate = Date().addingTimeInterval(newRemaining)

        self.endDate = newEndDate
        self.totalDurationSeconds += seconds

        updateRemainingTime()
        persistActiveSession()
    }

    public func changeMode(to newMode: KeepAwakeMode) {
        self.mode = newMode
        guard isActive else { return }

        let preservedDuration: KeepAwakeDuration
        if isIndefinite {
            preservedDuration = .indefinite
        } else {
            let remaining = max(1, remainingSeconds)
            preservedDuration = .custom(remaining)
        }

        start(mode: newMode, duration: preservedDuration)
    }

    // MARK: - Timer & Calculations

    private func startTickerTimer() {
        stopTickerTimer()
        tickerTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTimerTick()
            }
        }
        if let timer = tickerTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopTickerTimer() {
        tickerTimer?.invalidate()
        tickerTimer = nil
    }

    private func handleTimerTick() {
        guard isActive else {
            stopTickerTimer()
            return
        }

        if isIndefinite {
            remainingFormatted = "Indefinite"
            progress = 1.0
            return
        }

        guard let targetEndDate = endDate else {
            stop()
            return
        }

        let diff = targetEndDate.timeIntervalSince(Date())

        if diff <= 0 {
            handleSessionExpired()
        } else {
            self.remainingSeconds = diff
            self.remainingFormatted = formatTimeInterval(diff)
            if totalDurationSeconds > 0 {
                self.progress = max(0.0, min(1.0, diff / totalDurationSeconds))
            }
        }
    }

    private func updateRemainingTime() {
        if isIndefinite {
            remainingFormatted = "Indefinite"
            progress = 1.0
            return
        }

        guard let targetEndDate = endDate else { return }
        let diff = max(0, targetEndDate.timeIntervalSince(Date()))
        self.remainingSeconds = diff
        self.remainingFormatted = formatTimeInterval(diff)
        if totalDurationSeconds > 0 {
            self.progress = max(0.0, min(1.0, diff / totalDurationSeconds))
        }
    }

    private func handleSessionExpired() {
        stop()
        sendExpiryNotificationIfNeeded()
    }

    private func sendExpiryNotificationIfNeeded() {
        let center = DistributedNotificationCenter.default()
        center.postNotificationName(
            NSNotification.Name("com.maclink.keepawake.expired"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func releaseCurrentAssertion() {
        if currentAssertionID != 0 {
            _ = assertionProvider.releaseAssertion(id: currentAssertionID)
            currentAssertionID = 0
        }
    }

    // MARK: - System Observers

    private func setupSystemObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter

        let wakeToken = wsCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSystemWake()
            }
        }
        notificationTokens.append(wakeToken)

        let clockToken = NotificationCenter.default.addObserver(
            forName: Notification.Name.NSSystemClockDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleClockOrTimeZoneChange()
            }
        }
        notificationTokens.append(clockToken)

        let tzToken = NotificationCenter.default.addObserver(
            forName: Notification.Name.NSSystemTimeZoneDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleClockOrTimeZoneChange()
            }
        }
        notificationTokens.append(tzToken)

        let termToken = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stop()
            }
        }
        notificationTokens.append(termToken)
    }

    private func handleSystemWake() {
        guard isActive else { return }
        if !isIndefinite, let targetEndDate = endDate {
            if targetEndDate.timeIntervalSinceNow <= 0 {
                handleSessionExpired()
            } else {
                updateRemainingTime()
            }
        }
    }

    private func handleClockOrTimeZoneChange() {
        guard isActive else { return }
        updateRemainingTime()
    }

    // MARK: - State Persistence

    private func persistActiveSession() {
        let defaults = UserDefaults.standard
        defaults.set(mode.rawValue, forKey: Keys.activeMode)
        defaults.set(isIndefinite, forKey: Keys.activeIsIndefinite)
        defaults.set(totalDurationSeconds, forKey: Keys.activeTotalDuration)

        if let targetEndDate = endDate {
            defaults.set(targetEndDate.timeIntervalSince1970, forKey: Keys.activeEndDate)
        } else {
            defaults.removeObject(forKey: Keys.activeEndDate)
        }

        if case .preset(let preset) = activeDuration {
            defaults.set(preset.rawValue, forKey: Keys.lastPreset)
        }
    }

    private func clearPersistentState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.activeEndDate)
        defaults.removeObject(forKey: Keys.activeTotalDuration)
        defaults.removeObject(forKey: Keys.activeIsIndefinite)
        defaults.removeObject(forKey: Keys.activeMode)
    }

    private func restoreSessionIfPersisted() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Keys.activeMode) != nil else { return }

        let modeRaw = defaults.string(forKey: Keys.activeMode) ?? KeepAwakeMode.displayAndSystem.rawValue
        let restoredMode = KeepAwakeMode(rawValue: modeRaw) ?? .displayAndSystem
        let isIndefinite = defaults.bool(forKey: Keys.activeIsIndefinite)
        let totalDuration = defaults.double(forKey: Keys.activeTotalDuration)

        if isIndefinite {
            start(mode: restoredMode, duration: .indefinite)
            return
        }

        let endTimestamp = defaults.double(forKey: Keys.activeEndDate)
        guard endTimestamp > 0 else {
            clearPersistentState()
            return
        }

        let savedEndDate = Date(timeIntervalSince1970: endTimestamp)
        let remaining = savedEndDate.timeIntervalSinceNow

        if remaining > 0 {
            start(mode: restoredMode, duration: .custom(remaining))
            self.totalDurationSeconds = max(totalDuration, remaining)
            self.endDate = savedEndDate
            updateRemainingTime()
        } else {
            clearPersistentState()
        }
    }

    // MARK: - Formatting Helpers

    public func formatTimeInterval(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(ceil(max(0, interval)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%dh %02dm %02ds", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%dm %02ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }

    public func formatTimeIntervalShort(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(ceil(max(0, interval)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else {
            return String(format: "%dm", max(1, minutes))
        }
    }
}
