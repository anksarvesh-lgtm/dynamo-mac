//
//  MeetingFlightService.swift
//  LiquidDynamo
//
//  Pre-Flight camera preview embedded inside calendar meeting join buttons.
//  Merged from Ledge.
//

import AVFoundation
import Combine
import SwiftUI

@MainActor
public final class MeetingFlightService: ObservableObject {
    public static let shared = MeetingFlightService()

    @Published public private(set) var isCameraActive: Bool = false
    @Published public private(set) var nextMeetingTitle: String = "Upcoming Call"
    @Published public private(set) var nextMeetingURL: URL? = nil

    private var captureSession: AVCaptureSession?

    private init() {}

    public func startCameraPreview() {
        guard !isCameraActive else { return }

        let session = AVCaptureSession()
        session.sessionPreset = .low

        guard let camera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else { return }

        session.addInput(input)
        session.startRunning()
        self.captureSession = session
        self.isCameraActive = true
    }

    public func stopCameraPreview() {
        captureSession?.stopRunning()
        captureSession = nil
        isCameraActive = false
    }
}

public struct MeetingFlightJoinButton: View {
    @ObservedObject var flight = MeetingFlightService.shared
    @State private var isHovering: Bool = false

    public init() {}

    public var body: some View {
        Button {
            if let url = flight.nextMeetingURL {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "video.fill")
                    .font(.system(size: 11))
                Text("Join Call")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.green.opacity(0.8))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                flight.startCameraPreview()
            } else {
                flight.stopCameraPreview()
            }
        }
    }
}
