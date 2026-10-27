//  BrightnessManager.swift
//  boringNotch
//
//  Created by JeanLouis on 08/22/24.

import AppKit
import Defaults

final class BrightnessManager: ObservableObject {
	static let shared = BrightnessManager()

	@Published private(set) var rawBrightness: Float = 0
	@Published private(set) var animatedBrightness: Float = 0
	@Published private(set) var lastChangeAt: Date = .distantPast

	private let visibleDuration: TimeInterval = 1.2
	private let client = XPCHelperClient.shared
	private var monitorTimer: Timer?

	private init() {
		refresh()
		startMonitor()
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
		let timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
			guard let self = self else { return }
			guard Defaults[.showNotchOSD] else { return }
			if let current = self.readDirectScreenBrightness() {
				if abs(current - self.rawBrightness) > 0.008 {
					Task { @MainActor [weak self] in
						guard let self = self else { return }
						self.publish(brightness: current, touchDate: true)
						LiquidViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(current))
						self.postBrightnessHUD(level: current)
					}
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
				isDraggable: true
			),
			pauseDismissalOnHover: true
		)
		LiveActivityCenter.shared.submit(activity)
	}

	func refresh() {
		if let direct = readDirectScreenBrightness() {
			publish(brightness: direct, touchDate: false)
			return
		}
		Task { @MainActor in
			if let current = await client.currentScreenBrightness() {
				publish(brightness: current, touchDate: false)
			}
		}
	}


	@discardableResult
	private func writeDirectScreenBrightness(_ value: Float) -> Bool {
		guard let fn = Self.setBrightnessFn else { return false }
		return fn(CGMainDisplayID(), value) == 0
	}

	@MainActor func setRelative(delta: Float) {
		let starting = readDirectScreenBrightness() ?? rawBrightness
		let target = max(0, min(1, starting + delta))
		if writeDirectScreenBrightness(target) {
			publish(brightness: target, touchDate: true)
		} else {
			Task { @MainActor in
				let ok = await client.setScreenBrightness(target)
				if ok {
					publish(brightness: target, touchDate: true)
				} else {
					refresh()
				}
			}
		}
		LiquidViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(target))
		postBrightnessHUD(level: target)
	}

	func setAbsolute(value: Float) {
		let clamped = max(0, min(1, value))
		if writeDirectScreenBrightness(clamped) {
			publish(brightness: clamped, touchDate: true)
		} else {
			Task { @MainActor in
				let ok = await client.setScreenBrightness(clamped)
				if ok {
					publish(brightness: clamped, touchDate: true)
				} else {
					refresh()
				}
			}
		}
	}

	private func publish(brightness: Float, touchDate: Bool) {
		DispatchQueue.main.async {
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

	private let visibleDuration: TimeInterval = 1.2
	private let client = XPCHelperClient.shared

	private init() { refresh() }

	var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

	func refresh() {
		Task { @MainActor in
			if let current = await client.currentKeyboardBrightness() {
				publish(brightness: current, touchDate: false)
			}
		}
	}

	@MainActor func setRelative(delta: Float) {
		Task { @MainActor in
			let starting = await client.currentKeyboardBrightness() ?? rawBrightness
			let target = max(0, min(1, starting + delta))
			let ok = await client.setKeyboardBrightness(target)
			if ok {
				publish(brightness: target, touchDate: true)
			} else {
				refresh()
			}
			LiquidViewCoordinator.shared.toggleSneakPeek(
				status: true,
				type: .backlight,
				value: CGFloat(target)
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
					iconName: "keyboard",
					value: Double(target),
					isDraggable: true
				),
				pauseDismissalOnHover: true
			)
			LiveActivityCenter.shared.submit(activity)
		}
	}

	func setAbsolute(value: Float) {
		let clamped = max(0, min(1, value))
		Task { @MainActor in
			let ok = await client.setKeyboardBrightness(clamped)
			if ok {
				publish(brightness: clamped, touchDate: true)
			} else {
				refresh()
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

