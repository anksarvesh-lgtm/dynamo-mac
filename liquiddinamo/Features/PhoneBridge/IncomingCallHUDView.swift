//
//  IncomingCallHUDView.swift
//  LiquidDynamo
//
//  Dynamic Island incoming & active cellular call card with fluid accept/decline capsules.
//

import SwiftUI

public struct IncomingCallHUDView: View {
    @ObservedObject var bridge = MacLinkBridgeService.shared

    public init() {}

    public var body: some View {
        if let call = bridge.incomingCall {
            // Incoming Call State
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: "phone.arrow.down.left.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 14))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(call.callerName)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(call.callerNumber.isEmpty ? "Incoming Cellular Call" : call.callerNumber)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                // Decline Button
                Button {
                    bridge.declineCall()
                } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.red.opacity(0.85)))
                }
                .buttonStyle(.plain)

                // Accept Button
                Button {
                    bridge.acceptCall()
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.green.opacity(0.85)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.88))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8))
            )
        } else if bridge.isCallActive {
            // Active Call State
            HStack(spacing: 12) {
                Image(systemName: "phone.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Call in Progress")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                    Text(formatDuration(bridge.activeCallDuration))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.green)
                }

                Spacer()

                Button {
                    bridge.endActiveCall()
                } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Circle().fill(Color.red.opacity(0.85)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.88))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8))
            )
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

