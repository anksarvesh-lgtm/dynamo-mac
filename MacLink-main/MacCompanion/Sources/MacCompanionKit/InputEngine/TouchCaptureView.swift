// SPDX-License-Identifier: MIT
import AppKit

public struct InputTelemetry: Sendable, Equatable {
    public let timestamp: TimeInterval
    public let deviceType: String
    public let eventName: String
    public let coordinates: CGPoint
    public let deltaX: CGFloat
    public let deltaY: CGFloat
    public let pressure: Float
    public let stage: Int
    public let details: String

    public init(
        timestamp: TimeInterval = Date().timeIntervalSinceReferenceDate,
        deviceType: String,
        eventName: String,
        coordinates: CGPoint = .zero,
        deltaX: CGFloat = 0,
        deltaY: CGFloat = 0,
        pressure: Float = 0,
        stage: Int = 0,
        details: String = ""
    ) {
        self.timestamp = timestamp
        self.deviceType = deviceType
        self.eventName = eventName
        self.coordinates = coordinates
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.pressure = pressure
        self.stage = stage
        self.details = details
    }
}

public protocol InputTelemetryDelegate: AnyObject, Sendable {
    func didCaptureInput(_ telemetry: InputTelemetry)
}

/// AppKit NSView subclass capturing multi-touch, pressure, magnification, and rotation events locally.
public final class TouchCaptureView: NSView {
    public weak var delegate: InputTelemetryDelegate?

    public override var acceptsFirstResponder: Bool { true }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupGestures()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGestures()
    }

    private func setupGestures() {
        wantsRestingTouches = true
        allowedTouchTypes = [.direct, .indirect]

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        addGestureRecognizer(click)

        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)

        let mag = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:)))
        addGestureRecognizer(mag)

        let rot = NSRotationGestureRecognizer(target: self, action: #selector(handleRotate(_:)))
        addGestureRecognizer(rot)

        let press = NSPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        addGestureRecognizer(press)
    }

    @objc private func handleClick(_ recognizer: NSClickGestureRecognizer) {
        let loc = recognizer.location(in: self)
        let telemetry = InputTelemetry(
            deviceType: "Trackpad",
            eventName: "ClickGesture",
            coordinates: loc,
            details: "Clicks: \(recognizer.numberOfClicksRequired)"
        )
        delegate?.didCaptureInput(telemetry)
    }

    @objc private func handlePan(_ recognizer: NSPanGestureRecognizer) {
        let loc = recognizer.location(in: self)
        let trans = recognizer.translation(in: self)
        let telemetry = InputTelemetry(
            deviceType: "Trackpad",
            eventName: "PanGesture",
            coordinates: loc,
            deltaX: trans.x,
            deltaY: trans.y,
            details: "State: \(recognizer.state.rawValue)"
        )
        delegate?.didCaptureInput(telemetry)
    }

    @objc private func handleMagnify(_ recognizer: NSMagnificationGestureRecognizer) {
        let loc = recognizer.location(in: self)
        let telemetry = InputTelemetry(
            deviceType: "Trackpad",
            eventName: "PinchToZoom",
            coordinates: loc,
            details: "Magnification: \(String(format: "%.3f", recognizer.magnification))"
        )
        delegate?.didCaptureInput(telemetry)
    }

    @objc private func handleRotate(_ recognizer: NSRotationGestureRecognizer) {
        let loc = recognizer.location(in: self)
        let telemetry = InputTelemetry(
            deviceType: "Trackpad",
            eventName: "RotateGesture",
            coordinates: loc,
            details: "RotationDegrees: \(String(format: "%.1f", recognizer.rotationInDegrees))"
        )
        delegate?.didCaptureInput(telemetry)
    }

    @objc private func handlePress(_ recognizer: NSPressGestureRecognizer) {
        let loc = recognizer.location(in: self)
        let telemetry = InputTelemetry(
            deviceType: "Trackpad",
            eventName: "LongPressGesture",
            coordinates: loc,
            details: "PressState: \(recognizer.state.rawValue)"
        )
        delegate?.didCaptureInput(telemetry)
    }

    public override func scrollWheel(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let telemetry = InputTelemetry(
            deviceType: event.subtype == .mouseEvent ? "Mouse" : "Trackpad",
            eventName: "ScrollWheel",
            coordinates: loc,
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            details: "Continuous: \(event.hasPreciseScrollingDeltas), Phase: \(event.phase.rawValue)"
        )
        delegate?.didCaptureInput(telemetry)
        super.scrollWheel(with: event)
    }

    public override func pressureChange(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let telemetry = InputTelemetry(
            deviceType: "ForceTouchTrackpad",
            eventName: "PressureChange",
            coordinates: loc,
            pressure: event.pressure,
            stage: event.stage,
            details: "Stage: \(event.stage), Pressure: \(String(format: "%.2f", event.pressure))"
        )
        delegate?.didCaptureInput(telemetry)
        super.pressureChange(with: event)
    }

    public override func touchesBegan(with event: NSEvent) {
        let touches = event.touches(matching: .touching, in: self)
        let telemetry = InputTelemetry(
            deviceType: "Trackpad",
            eventName: "TouchesBegan",
            details: "ActiveTouches: \(touches.count)"
        )
        delegate?.didCaptureInput(telemetry)
        super.touchesBegan(with: event)
    }

    public override func touchesEnded(with event: NSEvent) {
        let touches = event.touches(matching: .touching, in: self)
        let telemetry = InputTelemetry(
            deviceType: "Trackpad",
            eventName: "TouchesEnded",
            details: "RemainingTouches: \(touches.count)"
        )
        delegate?.didCaptureInput(telemetry)
        super.touchesEnded(with: event)
    }
}

