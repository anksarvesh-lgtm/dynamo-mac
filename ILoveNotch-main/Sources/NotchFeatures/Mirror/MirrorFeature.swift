// SPDX-License-Identifier: MIT
import AVFoundation
import NotchCore
import Observation
import SwiftUI

/// Camera permission, as the mirror needs it.
public enum CameraAccess: Equatable, Sendable {
    case notDetermined
    case denied
    case granted

    init() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: self = .granted
        case .notDetermined: self = .notDetermined
        default: self = .denied  // denied or restricted
        }
    }
}

/// A mirror from the front camera. The camera runs only while this tab is on screen and access is
/// granted, and stops the moment the notch closes or switches tabs; nothing is recorded. The
/// camera is asked for only when the user taps Continue.
@MainActor
@Observable
public final class MirrorFeature: NotchFeature {
    public let id = FeatureID.mirror
    public var phase: FeaturePhase = .stopped {
        didSet { update() }
    }
    public private(set) var access = CameraAccess()
    /// Whether frames are flowing; false before the camera starts and after it stops.
    public private(set) var isRunning = false
    /// No camera could be opened, for example on a Mac mini with none attached.
    public private(set) var cameraMissing = false

    @ObservationIgnored let camera = CameraSession()

    public init() {}

    public var view: some View { MirrorView(mirror: self) }

    /// The camera runs only while its picture can be seen.
    nonisolated static func runsCamera(phase: FeaturePhase, access: CameraAccess) -> Bool {
        phase == .foreground && access == .granted
    }

    public func requestAccess() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
    }

    private func update() {
        access = CameraAccess()
        let run = Self.runsCamera(phase: phase, access: access)
        camera.run(run) { [weak self] running, missing in
            Task { @MainActor in
                guard let self else { return }
                self.isRunning = running
                self.cameraMissing = missing
                Log.features.info("Mirror camera \(running ? "running" : "stopped", privacy: .public)")
            }
        }
    }
}

/// The capture session, confined to its own queue because starting and stopping it blocks for a
/// moment. Configured on first use with the built-in camera, or else the first one found.
final class CameraSession: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "cafe.opennotch.mirror", qos: .userInitiated)
    // Only touched on `queue`.
    private var configured = false

    /// Starts or stops the camera, then reports whether it runs and whether no camera was found.
    func run(_ running: Bool, completion: @escaping @Sendable (_ running: Bool, _ missing: Bool) -> Void) {
        queue.async { [self] in
            var missing = false
            if running {
                if !configured {
                    configured = configure()
                    missing = !configured
                }
                if configured, !session.isRunning { session.startRunning() }
            } else if session.isRunning {
                session.stopRunning()
            }
            completion(session.isRunning, missing)
        }
    }

    private func configure() -> Bool {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external], mediaType: .video, position: .unspecified)
        guard
            let device = discovery.devices.first(where: { $0.deviceType == .builtInWideAngleCamera })
                ?? discovery.devices.first,
            let input = try? AVCaptureDeviceInput(device: device)
        else { return false }
        session.beginConfiguration()
        // The mirror is a few hundred points wide: a VGA feed is plenty and keeps the camera cheap.
        session.sessionPreset = session.canSetSessionPreset(.vga640x480) ? .vga640x480 : .medium
        if session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()
        return !session.inputs.isEmpty
    }
}
