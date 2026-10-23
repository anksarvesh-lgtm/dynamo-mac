//
//  SettingsPrivacyView.swift
//  LiquidDynamo
//
//  Camera & Microphone Privacy Control Center:
//  Real-time preview and tuning of ambient liquid glow indicators
//  when camera or microphone hardware is accessed.
//

import AppKit
import Defaults
import SwiftUI

public struct SettingsPrivacyView: View {
    @Default(.cameraNotchGlowEnabled) private var cameraGlowEnabled
    @Default(.micNotchGlowEnabled) private var micGlowEnabled
    @Default(.privacyIndicatorsEnabled) private var masterEnabled

    @State private var previewState: String? = nil // "camera" or "mic"

    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Privacy Indicators")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Unobtrusive Liquid Glass glow around the notch whenever sensors activate")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $masterEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // Interactive Notch Preview Card
                notchPreviewCard
                    .padding(.horizontal, 24)

                // Privacy Indicator Modules
                indicatorsCard
                    .padding(.horizontal, 24)

                Spacer(minLength: 20)
            }
        }
    }

    // MARK: - Notch Simulator Preview Card
    private var notchPreviewCard: some View {
        VStack(spacing: 16) {
            Text("Simulated MacBook Notch Feedback")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            // Notch Container Simulation
            ZStack(alignment: .top) {
                // Top Screen Edge
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
                    .frame(height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )

                // Simulated Notch Body
                VStack(spacing: 0) {
                    UnevenRoundedRectangle(
                        bottomLeadingRadius: 12,
                        bottomTrailingRadius: 12,
                        style: .continuous
                    )
                    .fill(Color.black)
                    .frame(width: 170, height: 32)
                    .overlay(
                        // Ambient Liquid Glow Fill
                        Group {
                            if previewState == "camera" {
                                UnevenRoundedRectangle(
                                    bottomLeadingRadius: 12,
                                    bottomTrailingRadius: 12,
                                    style: .continuous
                                )
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.green.opacity(0.65),
                                            Color.mint.opacity(0.35)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .shadow(color: Color.green.opacity(0.8), radius: 14, x: 0, y: 4)
                            } else if previewState == "mic" {
                                UnevenRoundedRectangle(
                                    bottomLeadingRadius: 12,
                                    bottomTrailingRadius: 12,
                                    style: .continuous
                                )
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.orange.opacity(0.65),
                                            Color.yellow.opacity(0.35)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .shadow(color: Color.orange.opacity(0.8), radius: 14, x: 0, y: 4)
                            }
                        }
                    )
                }

                // Status text inside preview
                VStack {
                    Spacer()
                    if let p = previewState {
                        Text(p == "camera" ? "Camera Active (Liquid Emerald)" : "Microphone Active (Liquid Amber)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(p == "camera" ? Color.green : Color.orange)
                            .padding(.bottom, 12)
                    } else {
                        Text("Notch in idle state. Click below to test ambient glows.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .padding(.bottom, 12)
                    }
                }
            }
            .frame(height: 120)

            // Test Controls Row
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        previewState = previewState == "camera" ? nil : "camera"
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("Test Camera Glow")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(previewState == "camera" ? 0.3 : 0.1))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.green.opacity(0.4), lineWidth: 0.8))
                    )
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        previewState = previewState == "mic" ? nil : "mic"
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Color.orange).frame(width: 8, height: 8)
                        Text("Test Microphone Glow")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(previewState == "mic" ? 0.3 : 0.1))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.4), lineWidth: 0.8))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        )
    }

    // MARK: - Sensor Toggle Cards
    private var indicatorsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hardware Sensor Tracking")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            // Camera Glow Setting
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.2)).frame(width: 32, height: 32)
                    Image(systemName: "camera.fill").font(.system(size: 14)).foregroundStyle(Color.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Camera Sensor Active")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("Glows with soft liquid green. Replaces intrusive popups.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $cameraGlowEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            Divider().opacity(0.2)

            // Microphone Glow Setting
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.2)).frame(width: 32, height: 32)
                    Image(systemName: "mic.fill").font(.system(size: 14)).foregroundStyle(Color.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Microphone Sensor Active")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("Glows with soft liquid orange whenever input audio streams.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $micGlowEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        )
    }
}
