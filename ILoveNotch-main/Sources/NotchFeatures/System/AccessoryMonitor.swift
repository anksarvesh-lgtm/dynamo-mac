// SPDX-License-Identifier: MIT
import Foundation
import IOKit
import NotchCore

/// Experimental: shows a Bluetooth keyboard, mouse, or trackpad's battery when it connects. Apple's
/// accessories publish `BatteryPercent` in the I/O Registry, and IOKit announces new ones, so
/// nothing runs between connections. Other accessories, and AirPods, don't expose their battery
/// through public APIs.
@MainActor
public final class AccessoryMonitor {
    public var onActivity: ((Activity) -> Void)?
    public var isRunning: Bool { port != nil }

    private var port: IONotificationPortRef?
    private var iterator: io_iterator_t = 0

    public init() {}

    public func start() {
        guard port == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(port, .main)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { context, iterator in
            guard let context else { return }
            let monitor = Unmanaged<AccessoryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.drain(iterator, announce: true) }
        }
        let matching = IOServiceMatching("AppleDeviceManagementHIDEventService")
        guard
            IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, matching, callback, context, &iterator)
                == KERN_SUCCESS
        else {
            IONotificationPortDestroy(port)
            return
        }
        self.port = port
        drain(iterator, announce: false)  // arms the notification; what's already connected isn't news
    }

    public func stop() {
        guard let port else { return }
        IOObjectRelease(iterator)
        iterator = 0
        IONotificationPortDestroy(port)
        self.port = nil
    }

    /// What the notch shows for an accessory: its kind and its charge.
    nonisolated static func activity(product: String, percent: Int) -> Activity {
        let name = product.lowercased()
        let symbol =
            if name.contains("mouse") {
                "magicmouse.fill"
            } else if name.contains("trackpad") {
                "rectangle.and.hand.point.up.left.fill"
            } else if name.contains("keyboard") {
                "keyboard.fill"
            } else {
                "dot.radiowaves.left.and.right"
            }
        let percent = min(max(percent, 0), 100)
        return Activity(
            feature: nil, symbol: symbol, title: "\(percent)%", level: Double(percent) / 100, duration: .seconds(3))
    }

    private func drain(_ iterator: io_iterator_t, announce: Bool) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard announce,
                let product = Self.property(service, "Product") as? String,
                let percent = Self.property(service, "BatteryPercent") as? Int
            else { continue }
            onActivity?(Self.activity(product: product, percent: percent))
        }
    }

    private static func property(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
