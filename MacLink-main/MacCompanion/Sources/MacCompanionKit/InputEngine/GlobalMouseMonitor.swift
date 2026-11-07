// SPDX-License-Identifier: MIT
import AppKit

public final class GlobalMouseMonitor: @unchecked Sendable {
    private var globalMonitorToken: Any?
    private var localMonitorToken: Any?
    private let lock = NSLock()

    public var onPointerEvent: ((InputTelemetry) -> Void)?

    public init() {}

    public func startMonitoring() {
        lock.lock()
        defer { lock.unlock() }

        guard globalMonitorToken == nil else { return }

        let mask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDown,
            .leftMouseUp,
            .rightMouseDown,
            .rightMouseUp,
            .scrollWheel,
            .leftMouseDragged,
            .rightMouseDragged
        ]

        // 1. Global observation for events sent to other apps
        globalMonitorToken = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleEvent(event, isGlobal: true)
        }

        // 2. Local observation for in-app events
        localMonitorToken = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleEvent(event, isGlobal: false)
            return event
        }
    }

    private func handleEvent(_ event: NSEvent, isGlobal: Bool) {
        let name: String
        switch event.type {
        case .mouseMoved: name = "MouseMoved"
        case .leftMouseDown: name = "LeftMouseDown"
        case .leftMouseUp: name = "LeftMouseUp"
        case .rightMouseDown: name = "RightMouseDown"
        case .rightMouseUp: name = "RightMouseUp"
        case .scrollWheel: name = "ScrollWheel"
        case .leftMouseDragged: name = "LeftMouseDragged"
        case .rightMouseDragged: name = "RightMouseDragged"
        default: name = "OtherMouseEvent"
        }

        let loc = NSEvent.mouseLocation
        let telemetry = InputTelemetry(
            deviceType: isGlobal ? "GlobalPointer" : "LocalPointer",
            eventName: name,
            coordinates: loc,
            deltaX: event.deltaX,
            deltaY: event.deltaY,
            details: "Clicks: \(event.clickCount), DeltaZ: \(event.deltaZ)"
        )
        onPointerEvent?(telemetry)
    }

    public func stopMonitoring() {
        lock.lock()
        defer { lock.unlock() }

        if let token = globalMonitorToken {
            NSEvent.removeMonitor(token)
            globalMonitorToken = nil
        }
        if let token = localMonitorToken {
            NSEvent.removeMonitor(token)
            localMonitorToken = nil
        }
    }

    deinit {
        stopMonitoring()
    }
}

