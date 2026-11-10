//
//  MacLinkCallsView.swift
//  LiquidDynamo
//
//  MacLink Telephony Hub: Touch Dialpad, Recent Call Log, and Hands-Free
//  Bluetooth HFP Telephony Routing.
//

import AppKit
import SwiftUI

public struct MacLinkCallsView: View {
    @ObservedObject private var bridge = MacLinkBridgeService.shared
    @State private var dialedDigits: String = ""

    private let dialpadButtons: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["*", "0", "#"]
    ]

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            // Left Pane: Recent Calls List
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Call History")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.white)
                    Spacer()
                    Text("\(bridge.recentCalls.count) calls")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .padding(16)

                Divider().opacity(0.12)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(bridge.recentCalls) { call in
                            callHistoryRow(call)
                        }
                    }
                    .padding(8)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color(white: 0.10).opacity(0.5))

            Divider().opacity(0.12)

            // Right Pane: Touch Dialpad & Ongoing Call Card
            VStack(spacing: 20) {
                if bridge.isCallActive {
                    activeCallCard
                } else {
                    dialpadCard
                }
            }
            .frame(width: 340)
            .padding(24)
            .background(Color(white: 0.09).opacity(0.8))
        }
    }

    private func callHistoryRow(_ call: PhoneCallHistoryItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: call.type == .missed ? "phone.down.left.fill" : (call.type == .outgoing ? "phone.arrow.up.right.fill" : "phone.arrow.down.left.fill"))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(call.type == .missed ? Color.red : (call.type == .outgoing ? Color.blue : Color.green))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(0.06)))

            VStack(alignment: .leading, spacing: 2) {
                Text(call.callerName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                Text(call.callerNumber)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.5))
            }

            Spacer()

            Button {
                bridge.dialNumber(call.callerNumber)
            } label: {
                Image(systemName: "phone.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.green)
                    .padding(8)
                    .background(Circle().fill(Color.green.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.03)))
    }

    private var dialpadCard: some View {
        VStack(spacing: 16) {
            // Number Display
            ZStack {
                Text(dialedDigits.isEmpty ? "Enter Number" : dialedDigits)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(dialedDigits.isEmpty ? Color.white.opacity(0.3) : Color.white)
                    .lineLimit(1)
                    .frame(height: 38)
            }
            .padding(.horizontal, 12)

            // Dialpad Buttons Grid
            VStack(spacing: 12) {
                ForEach(dialpadButtons, id: \.self) { row in
                    HStack(spacing: 16) {
                        ForEach(row, id: \.self) { digit in
                            Button {
                                dialedDigits.append(digit)
                            } label: {
                                Text(digit)
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(Color.white)
                                    .frame(width: 60, height: 60)
                                    .background(Circle().fill(Color.white.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Bottom Actions (Call & Backspace)
            HStack(spacing: 24) {
                // Clear button
                Button {
                    if !dialedDigits.isEmpty {
                        dialedDigits.removeLast()
                    }
                } label: {
                    Image(systemName: "delete.left.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                // Call button
                Button {
                    guard !dialedDigits.isEmpty else { return }
                    bridge.dialNumber(dialedDigits)
                    dialedDigits = ""
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Color.green))
                        .shadow(color: Color.green.opacity(0.4), radius: 8, x: 0, y: 3)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
    }

    private var activeCallCard: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(Color.green.opacity(0.2))
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "phone.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.green)
                )

            VStack(spacing: 4) {
                Text(bridge.incomingCall?.callerName ?? "Active Call")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white)

                Text(formatDuration(bridge.activeCallDuration))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.green)
            }

            HStack(spacing: 20) {
                Button {
                    bridge.endActiveCall()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "phone.down.fill")
                        Text("End Call")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.red))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.12))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

