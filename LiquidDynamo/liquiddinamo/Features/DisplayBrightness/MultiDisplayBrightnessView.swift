//
//  MultiDisplayBrightnessView.swift
//  boringNotch
//
//  Created for Boring Notch
//

import SwiftUI

struct MultiDisplayBrightnessView: View {
    @ObservedObject var brightnessService = MultiDisplayBrightnessService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Label("DISPLAYS & BRIGHTNESS", systemImage: "sun.max.fill")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(brightnessService.displays.count) \(brightnessService.displays.count == 1 ? "DISPLAY" : "DISPLAYS")")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if brightnessService.displays.isEmpty {
                Text("No displays detected")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(brightnessService.displays) { display in
                        DisplayRowView(display: display)
                    }
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 20, tint: .indigo)
        .onAppear {
            brightnessService.refreshDisplays()
        }
    }
}

// MARK: - Display Row View

struct DisplayRowView: View {
    @ObservedObject var display: ManagedDisplay
    @ObservedObject var brightnessService = MultiDisplayBrightnessService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Display Title & Method Badge
            HStack(spacing: 6) {
                Premium3DIconView(.desktopMac, size: 14)

                Text(display.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)

                Spacer()

                // Method Badge
                badgeView(for: display.controlMethod)
            }

            if display.isControllable {
                // Slider Row
                HStack(spacing: 10) {
                    Premium3DIconView(name: brightnessIconName(for: display.brightness), size: 14)
                        .frame(width: 16)

                    // Interactive Slider
                    GeometryReader { geo in
                        let progress = CGFloat(display.brightness)
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                                .frame(height: 8)

                            Capsule()
                                .fill(
                                    display.controlMethod == .softwareDimming
                                        ? Color.orange
                                        : Color.accentColor
                                )
                                .frame(width: max(0, min(geo.size.width * progress, geo.size.width)), height: 8)
                        }
                        .frame(height: geo.size.height, alignment: .center)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { gesture in
                                    let newProgress = max(0.0, min(1.0, Float(gesture.location.x / geo.size.width)))
                                    brightnessService.setBrightness(newProgress, for: display)
                                }
                        )
                    }
                    .frame(height: 20)

                    // Percentage Readout
                    Text("\(Int(round(display.brightness * 100)))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(width: 38, alignment: .trailing)
                }
            } else {
                // Clear message when display cannot be controlled
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                    Text("This display does not support hardware brightness or software dimming.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Subviews & Helpers

    @ViewBuilder
    private func badgeView(for method: BrightnessControlMethod) -> some View {
        HStack(spacing: 3) {
            if method == .softwareDimming {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 4, height: 4)
            }
            Text(method.rawValue)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            method == .softwareDimming
                ? Color.orange.opacity(0.15)
                : Color.white.opacity(0.08)
        )
        .foregroundStyle(
            method == .softwareDimming
                ? Color.orange
                : Color.secondary
        )
        .clipShape(Capsule())
    }

    private func brightnessIconName(for value: Float) -> String {
        if value < 0.33 {
            return "sun.min.fill"
        } else if value < 0.66 {
            return "sun.medium.fill"
        } else {
            return "sun.max.fill"
        }
    }
}
