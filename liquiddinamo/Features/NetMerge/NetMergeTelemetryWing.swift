//
//  NetMergeTelemetryWing.swift
//  LiquidDynamo
//
//  Dynamic notch telemetry capsule and HUD wing for NetMerge multi-network link bonding.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import SwiftUI
import Defaults

public struct NetMergeTelemetryWing: View {
    @ObservedObject private var engine = NetMergeEngine.shared

    @State private var isHovering = false

    public init() {}

    public var body: some View {
        HStack(spacing: 8) {
            // Animated Status Glyphs
            ZStack {
                Circle()
                    .fill(statusGlowColor.opacity(0.2))
                    .frame(width: 22, height: 22)

                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("NetMerge")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)

                    if engine.isRunning {
                        Text("• \(engine.detectedAdaptersCount) Links")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(statusColor)
                    }
                }

                if engine.isRunning {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.green)
                        Text(formatSpeed(engine.totalDownloadSpeedMbps))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))

                        Image(systemName: "arrow.up")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.cyan)
                        Text(formatSpeed(engine.totalUploadSpeedMbps))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                } else {
                    Text("Offline • Click to bond")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            Spacer(minLength: 0)

            // Quick Toggle Button
            Button {
                engine.toggle()
            } label: {
                Image(systemName: engine.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.white.opacity(0.15)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(statusColor.opacity(isHovering ? 0.4 : 0.15), lineWidth: 1)
                )
        )
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                isHovering = hovering
            }
        }
    }

    private var statusColor: Color {
        switch engine.serviceState {
        case .active:
            return Color(red: 0.18, green: 0.82, blue: 0.45) // emerald green
        case .degraded:
            return Color(red: 0.2, green: 0.65, blue: 0.95) // cyan blue
        case .starting:
            return Color.orange
        case .stopped:
            return Color.secondary
        case .error:
            return Color.red
        }
    }

    private var statusGlowColor: Color {
        statusColor
    }

    private func formatSpeed(_ mbps: Double) -> String {
        if mbps >= 1000 {
            return String(format: "%.1f Gb/s", mbps / 1000.0)
        } else if mbps >= 1.0 {
            return String(format: "%.1f Mb/s", mbps)
        } else {
            return String(format: "%.0f Kb/s", mbps * 1000.0)
        }
    }
}
