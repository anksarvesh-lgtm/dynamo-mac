//  BrightnessManager.swift
//  LiquidDynamo
//
//  LiquidDynamo Core Team

import AppKit
import Defaults

final class BrightnessManager: ObservableObject {
	static let shared = BrightnessManager()

	@Published private(set) var rawBrightness: Float = 0
	@Published private(set) var animatedBrightness: Float = 0
	@Published private(set) var lastChangeAt: Date = .distantPast
	@Published private(set) var isBrightnessAvailable: Bool = false

	private let visibleDuration: TimeInterval = 1.2
	private let client = XPCHelperClient.shared
	private var monitorTimer: Timer?

	private var osdObserver: Defaults.Observation?
	private var screenParamsObserver: NSObjectProtocol?

	private init() {
		refresh()
		osdObserver = Defaults.observe(.showNotchOSD) { [weak self] change in
			if change.newValue {
				self?.startMonitor()
			} else {
				self?.stopMonitor()
			}
		}
		screenParamsObserver = NotificationCenter.default.addObserver(
			forName: NSApplication.didChangeScreenParametersNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
			self?.refresh()
			self?.updateMonitorState()
		}
		if Defaults[.showNotchOSD] {
			startMonitor()
		}
	}

	deinit {
		stopMonitor()
		if let observer = screenParamsObserver {
			NotificationCenter.default.removeObserver(observer)
		}
	}

	func updateMonitorState() {
		if Defaults[.showNotchOSD] {
			startMonitor()
		} else {
			stopMonitor()
		}
	}

	func stopMonitor() {
		monitorTimer?.invalidate()
		monitorTimer = nil
	}

	var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

	private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
	private typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

	private static let displayServicesHandle: UnsafeMutableRawPointer? = {
		let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
		return dlopen(path, RTLD_LAZY)
	}()

	private static let getBrightnessFn: GetBrightnessFn? = {
		guard let handle = displayServicesHandle,
		      let sym = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
		return unsafeBitCast(sym, to: GetBrightnessFn.self)
	}()

	private static let setBrightnessFn: SetBrightnessFn? = {
		guard let handle = displayServicesHandle,
		      let sym = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
		return unsafeBitCast(sym, to: SetBrightnessFn.self)
	}()

	private func readDirectScreenBrightness() -> Float? {
		guard let fn = Self.getBrightnessFn else { return nil }
		var b: Float = 0
		if fn(CGMainDisplayID(), &b) == 0 {
			return b
		}
		return nil
	}

	private func startMonitor() {
		monitorTimer?.invalidate()
		guard Defaults[.showNotchOSD],
		      readDirectScreenBrightness() != nil || isBrightnessAvailable else {
			monitorTimer = nil
			return
		}
		let timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
			guard let self = self else { return }
			guard Defaults[.showNotchOSD] else {
				self.stopMonitor()
				return
			}
			guard let current = self.readDirectScreenBrightness() else {
				self.stopMonitor()
				self.refresh()
				return
			}
			if abs(current - self.rawBrightness) > 0.008 {
				Task { @MainActor [weak self] in
					guard let self = self else { return }
					self.publish(brightness: current, touchDate: true)
					LiquidViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(current))
					self.postBrightnessHUD(level: current)
				}
			}
		}
		timer.tolerance = 0.2
		monitorTimer = timer
	}

	@MainActor
	private func postBrightnessHUD(level: Float) {
		let clamped = max(0, min(1, Double(level)))
		let icon = clamped > 0.5 ? "sun.max.fill" : "sun.min.fill"
		let activity = LiveActivity(
			id: "brightness_hud",
			source: "brightness",
			kind: .hud,
			priority: LiveActivityPriority.hud,
			tint: .orange,
			duration: 1.5,
			coalescingKey: "brightness",
			payload: LiveActivityPayload(
				title: String(localized: "Brightness"),
				subtitle: "\(Int(round(clamped * 100)))%",
				iconName: icon,
				value: clamped,
				isDraggable: isBrightnessAvailable
			),
			pauseDismissalOnHover: true
		)
		LiveActivityCenter.shared.submit(activity)
	}

	func refresh() {
		if let direct = readDirectScreenBrightness() {
			publish(brightness: direct, touchDate: false)
			updateMonitorState()
			return
		}
		Task { @MainActor in
			if let current = await self.client.currentScreenBrightness() {
				self.publish(brightness: current, touchDate: false)
				self.updateMonitorState()
			} else {
				self.isBrightnessAvailable = false
				self.stopMonitor()
			}
		}
	}


	@discardableResult
	private func writeDirectScreenBrightness(_ value: Float) -> Bool {
		guard let fn = Self.setBrightnessFn else { return false }
		return fn(CGMainDisplayID(), value) == 0
	}

	@MainActor func setRelative(delta: Float) {
		if let outcome = applyDirectRelative(delta: delta) {
			_ = outcome
			return
		}
		setRelativeWithSafetyReport(delta: delta) { _, _ in }
	}

	@MainActor
	@discardableResult
	func setRelativeWithSafetyReport(
		delta: Float,
		onAsyncOutcome: @escaping @MainActor (Bool, Bool) -> Void
	) -> (changed: Bool, atRail: Bool)? {
		if let directOutcome = applyDirectRelative(delta: delta) {
			return directOutcome
		}

		Task { @MainActor in
			guard let starting = await self.client.currentScreenBrightness() else {
				self.isBrightnessAvailable = false
				self.stopMonitor()
				onAsyncOutcome(false, false)
				return
			}
			if (delta > 0 && starting >= 0.999) || (delta < 0 && starting <= 0.001) {
				self.publish(brightness: starting, touchDate: true)
				LiquidViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(starting))
				self.postBrightnessHUD(level: starting)
				onAsyncOutcome(false, true)
				return
			}
			let target = max(0, min(1, starting + delta))
			let ok = await self.client.setScreenBrightness(target)
			if ok {
				let actual = await self.client.currentScreenBrightness() ?? target
				self.publish(brightness: actual, touchDate: true)
				LiquidViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(actual))
				self.postBrightnessHUD(level: actual)
				onAsyncOutcome(abs(actual - starting) > 0.0005 || target != starting, false)
			} else {
				self.refresh()
				onAsyncOutcome(false, false)
			}
		}
		return nil
	}

	@MainActor
	private func applyDirectRelative(delta: Float) -> (changed: Bool, atRail: Bool)? {
		guard let starting = readDirectScreenBrightness() else {
			return nil
		}
		if (delta > 0 && starting >= 0.999) || (delta < 0 && starting <= 0.001) {
			publish(brightness: starting, touchDate: true)
			LiquidViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(starting))
			postBrightnessHUD(level: starting)
			return (false, true)
		}
		let target = max(0, min(1, starting + delta))
		guard writeDirectScreenBrightness(target) else {
			return nil
		}
		let actual = readDirectScreenBrightness() ?? target
		publish(brightness: actual, touchDate: true)
		LiquidViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(actual))
		postBrightnessHUD(level: actual)
		return (abs(actual - starting) > 0.0005 || target != starting, false)
	}

	func setAbsolute(value: Float) {
		let clamped = max(0, min(1, value))
		if writeDirectScreenBrightness(clamped) {
			publish(brightness: clamped, touchDate: true)
		} else {
			Task { @MainActor in
				let ok = await self.client.setScreenBrightness(clamped)
				if ok {
					self.publish(brightness: clamped, touchDate: true)
				} else {
					self.refresh()
				}
			}
		}
	}

	private func publish(brightness: Float, touchDate: Bool) {
		DispatchQueue.main.async {
			self.isBrightnessAvailable = true
			if self.rawBrightness != brightness || touchDate {
				if touchDate { self.lastChangeAt = Date() }
				self.rawBrightness = brightness
				self.animatedBrightness = brightness
			}
		}
	}
}

// (DisplayServices helpers moved into XPC helper)

// MARK: - Keyboard Backlight Controller
final class KeyboardBacklightManager: ObservableObject {
	static let shared = KeyboardBacklightManager()

	@Published private(set) var rawBrightness: Float = 0
	@Published private(set) var lastChangeAt: Date = .distantPast
	@Published private(set) var isKeyboardBacklightAvailable: Bool = false

	private let visibleDuration: TimeInterval = 1.2
	private let client = XPCHelperClient.shared

	private init() { refresh() }

	var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

	func refresh() {
		Task { @MainActor in
			let available = await self.client.isKeyboardBrightnessAvailable()
			if available, let current = await self.client.currentKeyboardBrightness() {
				self.isKeyboardBacklightAvailable = true
				self.publish(brightness: current, touchDate: false)
			} else {
				self.isKeyboardBacklightAvailable = false
			}
		}
	}

	@MainActor func setRelative(delta: Float) {
		setRelativeWithSafetyReport(delta: delta) { _, _ in }
	}

	@MainActor
	func setRelativeWithSafetyReport(
		delta: Float,
		onOutcome: @escaping @MainActor (Bool, Bool) -> Void
	) {
		Task { @MainActor in
			guard await self.client.isKeyboardBrightnessAvailable(),
			      let starting = await self.client.currentKeyboardBrightness() else {
				self.isKeyboardBacklightAvailable = false
				onOutcome(false, false)
				return
			}
			self.isKeyboardBacklightAvailable = true
			if (delta > 0 && starting >= 0.999) || (delta < 0 && starting <= 0.001) {
				self.publish(brightness: starting, touchDate: true)
				self.postKeyboardHUD(level: starting)
				onOutcome(false, true)
				return
			}
			let target = max(0, min(1, starting + delta))
			let ok = await self.client.setKeyboardBrightness(target)
			if ok {
				let actual = await self.client.currentKeyboardBrightness() ?? target
				self.publish(brightness: actual, touchDate: true)
				self.postKeyboardHUD(level: actual)
				onOutcome(abs(actual - starting) > 0.0005 || target != starting, false)
			} else {
				self.refresh()
				onOutcome(false, false)
			}
		}
	}

	@MainActor
	private func postKeyboardHUD(level: Float) {
		LiquidViewCoordinator.shared.toggleSneakPeek(
			status: true,
			type: .backlight,
			value: CGFloat(level)
		)
		let activity = LiveActivity(
			id: "keyboard_brightness_hud",
			source: "keyboard_brightness",
			kind: .hud,
			priority: LiveActivityPriority.hud,
			tint: .cyan,
			duration: 1.5,
			coalescingKey: "keyboard_brightness",
			payload: LiveActivityPayload(
				title: String(localized: "Keyboard"),
				subtitle: "\(Int(round(max(0, min(1, level)) * 100)))%",
				iconName: "keyboard",
				value: Double(level),
				isDraggable: false
			),
			pauseDismissalOnHover: true
		)
		LiveActivityCenter.shared.submit(activity)
	}

	func setAbsolute(value: Float) {
		let clamped = max(0, min(1, value))
		Task { @MainActor in
			let ok = await self.client.setKeyboardBrightness(clamped)
			if ok {
				self.isKeyboardBacklightAvailable = true
				self.publish(brightness: clamped, touchDate: true)
			} else {
				self.refresh()
			}
		}
	}

	private func publish(brightness: Float, touchDate: Bool) {
		DispatchQueue.main.async {
			if self.rawBrightness != brightness || touchDate {
				if touchDate { self.lastChangeAt = Date() }
				self.rawBrightness = brightness
			}
		}
	}
}

