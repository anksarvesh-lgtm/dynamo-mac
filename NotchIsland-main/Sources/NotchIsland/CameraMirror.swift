import AVFoundation
import SwiftUI

/// A quick camera check before a meeting.
struct CameraMirrorView: NSViewRepresentable {
    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.start()
        return view
    }
    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {}
    static func dismantleNSView(_ nsView: CameraPreviewNSView, coordinator: ()) { nsView.stop() }
}

final class CameraPreviewNSView: NSView {
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private let label = NSTextField(labelWithString: "")

    func start() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 11)
        label.alignment = .center
        label.stringValue = "Starting camera…"
        addSubview(label)
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async { ok ? self.configure() : self.denied() }
            }
        default: denied()
        }
    }

    private func denied() {
        label.stringValue = "Camera access is off for NotchIsland (System Settings → Privacy & Security → Camera)."
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { denied(); return }
        session.beginConfiguration()
        session.sessionPreset = .medium
        if session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        if let c = layer.connection, c.isVideoMirroringSupported {
            c.automaticallyAdjustsVideoMirroring = false
            c.isVideoMirrored = true
        }
        self.layer?.addSublayer(layer)
        preview = layer
        label.isHidden = true
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }

    func stop() {
        if session.isRunning { session.stopRunning() }
    }

    override func layout() {
        super.layout()
        preview?.frame = bounds
        label.frame = bounds.insetBy(dx: 12, dy: 0)
    }
}
