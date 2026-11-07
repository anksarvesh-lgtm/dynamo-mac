// SPDX-License-Identifier: MIT
import AVFoundation
import SwiftUI

/// The mirror tab: the camera flipped like a mirror, or the step it needs first.
struct MirrorView: View {
    let mirror: MirrorFeature

    var body: some View {
        switch mirror.access {
        case .notDetermined:
            FeatureUnavailableView(
                symbol: "web.camera", title: "A mirror in your notch",
                message: "Uses the camera only while this tab is open. Nothing is recorded.",
                action: ("Continue", mirror.requestAccess))  // App Review 5.1.1(iv): not "Allow"
        case .denied:
            FeatureUnavailableView(
                symbol: "video.slash", title: "Camera access is off",
                message: "Allow ILoveNotch in System Settings › Privacy & Security › Camera.",
                action: ("Open Privacy Settings", { NSWorkspace.shared.open(.privacySettings("Privacy_Camera")) }))
        case .granted where mirror.cameraMissing:
            FeatureUnavailableView(
                symbol: "video.slash", title: "No camera", message: "Connect a camera to use the mirror.")
        case .granted:
            CameraPreview(session: mirror.camera.session)
                .scaleEffect(x: -1, y: 1)  // a mirror, not a photo
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    if !mirror.isRunning { ProgressView().controlSize(.small) }
                }
                .accessibilityLabel("Camera mirror")
        }
    }
}

/// The capture session's live picture, filling the tab.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer = preview
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
