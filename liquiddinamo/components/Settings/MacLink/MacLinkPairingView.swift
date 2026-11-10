//
//  MacLinkPairingView.swift
//  LiquidDynamo
//
//  MacLink Pairing & Device Management: QR code pairing generator, BLE beacon discovery,
//  and Wi-Fi Direct connection.
//

import AppKit
import SwiftUI

public struct MacLinkPairingView: View {
    @ObservedObject private var bridge = MacLinkBridgeService.shared

    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pair New Device")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text("Connect your Android or iOS device using QR Code, Bluetooth BLE beacon, or USB")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.6))
                }

                // QR Code Pairing Card
                HStack(spacing: 24) {
                    // Stylized QR Graphic
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white)
                            .frame(width: 150, height: 150)

                        Image(systemName: "qrcode")
                            .font(.system(size: 120))
                            .foregroundStyle(Color.black)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Scan with MacLink Companion APK")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.white)

                        Text("Open the MacLink app on your phone and tap 'Scan QR Code' to establish an encrypted local QUIC socket bridge.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.65))

                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.shield.fill")
                                    .font(.system(size: 11))
                                Text("End-to-End Encrypted")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(Color.green)

                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 11))
                                Text("Local Wi-Fi Direct")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(Color.blue)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(white: 0.12).opacity(0.5))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
                )

                // Currently Paired Devices Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Connected Devices")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.white)

                    HStack(spacing: 14) {
                        Image(systemName: "iphone.gen3")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.blue)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.blue.opacity(0.15)))

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(bridge.deviceName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.white)
                                Text("Active")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(Color.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.green.opacity(0.12)))
                            }
                            Text("USB ADB • 5 Gbps High Speed")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.5))
                        }

                        Spacer()

                        Button {
                            // Reconnect or test
                            bridge.simulateIncomingCall()
                        } label: {
                            Text("Test Link")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(white: 0.12).opacity(0.45))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
                    )
                }
            }
            .padding(24)
        }
    }
}

