import AppKit
import Observation

/// System accessibility display options, kept live via NSWorkspace notification.
@MainActor
@Observable
final class AccessibilityMonitor {
    private(set) var reduceMotion = false
    private(set) var reduceTransparency = false
    private(set) var increaseContrast = false
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        read()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.read() }
        }
    }

    private func read() {
        let ws = NSWorkspace.shared
        reduceMotion = ws.accessibilityDisplayShouldReduceMotion
        reduceTransparency = ws.accessibilityDisplayShouldReduceTransparency
        increaseContrast = ws.accessibilityDisplayShouldIncreaseContrast
    }
}
