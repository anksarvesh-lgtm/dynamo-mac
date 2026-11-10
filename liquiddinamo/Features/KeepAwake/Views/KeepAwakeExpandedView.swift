//
//  KeepAwakeExpandedView.swift
//  LiquidDynamo
//
//  Expanded Dynamic Island dashboard for the Keep Awake subsystem.
//  Includes mode selection, quick presets, custom duration input,
//  live countdown ring, session controls, and clamshell mode guidance.
//

import SwiftUI

public struct KeepAwakeExpandedView: View {
    @ObservedObject private var manager = KeepAwakeManager.shared
    @State private var customHours: Int = 1
    @State private var customMinutes: Int = 30
    @State private var showCustomPicker: Bool = false
    @State private var customError: String? = nil

    public init() {}

    public var body: some View {
        VStack(spacing: 14) {
            // Header: Title & Active Badge
            headerRow

            if manager.isActive {
                // Active session dashboard
                activeSessionCard
            } else {
                // Inactive configuration panel
                inactiveSetupCard
            }

            // Clamshell / Lid-Close Explanatory Note
            clamshellNoticeFooter
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: manager.isActive)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showCustomPicker)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                Image(systemName: manager.isActive ? "bolt.shield.fill" : "bolt.shield")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(manager.isActive ? Color.orange : Color.white.opacity(0.8))

                Text("Keep Awake")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }

            Spacer()

            // Status Pill
            HStack(spacing: 5) {
                Circle()
                    .fill(manager.isActive ? Color.green : Color.white.opacity(0.3))
                    .frame(width: 6, height: 6)

                Text(manager.isActive ? "ACTIVE" : "IDLE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(manager.isActive ? Color.green : Color.white.opacity(0.5))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(manager.isActive ? Color.green.opacity(0.12) : Color.white.opacity(0.06))
            )
            .overlay(
                Capsule().stroke(manager.isActive ? Color.green.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    // MARK: - Active Session Card

    private var activeSessionCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Circular Progress Ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 5)
                        .frame(width: 58, height: 58)

                    if manager.isIndefinite {
                        Image(systemName: "infinity")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color.orange)
                    } else {
                        Circle()
                            .trim(from: 0.0, to: CGFloat(manager.progress))
                            .stroke(
                                LinearGradient(
                                    colors: [Color.orange, Color.yellow],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 58, height: 58)
                            .animation(.linear(duration: 0.5), value: manager.progress)

                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.orange)
                    }
                }

                // Countdown & Mode Details
                VStack(alignment: .leading, spacing: 3) {
                    Text(manager.remainingFormatted.isEmpty ? "Active" : manager.remainingFormatted)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)

                    Text(manager.mode.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.85))

                    Text(manager.mode.subtitle)
                        .font(.system(size: 9.5))
                        .foregroundColor(Color.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer()
            }

            Divider()
                .background(Color.white.opacity(0.08))

            // Action Buttons: +15 Min, Mode Switch, Stop
            HStack(spacing: 8) {
                if !manager.isIndefinite {
                    Button {
                        manager.extend(by: 15 * 60)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 10, weight: .semibold))
                            Text("+15 min")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Extend current session by 15 minutes")
                }

                // Mode Switch button
                Button {
                    let nextMode: KeepAwakeMode = manager.mode == .system ? .displayAndSystem : .system
                    manager.changeMode(to: nextMode)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: manager.mode == .system ? "display" : "cpu")
                            .font(.system(size: 10, weight: .semibold))
                        Text(manager.mode == .system ? "Add Display" : "System Only")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                // Stop Button
                Button {
                    manager.stop()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("Stop")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(Color.red.opacity(0.95))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.18))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.red.opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Inactive Setup Card

    private var inactiveSetupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Mode Selector: System vs Display + System
            VStack(alignment: .leading, spacing: 6) {
                Text("MODE")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.45))
                    .tracking(0.5)

                HStack(spacing: 8) {
                    ForEach(KeepAwakeMode.allCases) { m in
                        let isSelected = manager.mode == m
                        Button {
                            manager.mode = m
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: m.iconName)
                                    .font(.system(size: 11, weight: .medium))
                                Text(m.shortTitle)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(isSelected ? .white : Color.white.opacity(0.65))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isSelected ? Color.orange.opacity(0.22) : Color.white.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSelected ? Color.orange.opacity(0.5) : Color.white.opacity(0.06), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(manager.mode.subtitle)
                    .font(.system(size: 9.5))
                    .foregroundColor(Color.white.opacity(0.5))
                    .padding(.top, 2)
            }

            Divider()
                .background(Color.white.opacity(0.06))

            // Presets Selector
            VStack(alignment: .leading, spacing: 6) {
                Text("QUICK PRESETS")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.45))
                    .tracking(0.5)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(KeepAwakePreset.allCases) { preset in
                        Button {
                            manager.start(mode: manager.mode, duration: .preset(preset))
                        } label: {
                            Text(preset.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(Color.white.opacity(0.07))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    // Custom Duration Toggle Button
                    Button {
                        showCustomPicker.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Custom")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(showCustomPicker ? Color.orange : Color.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(showCustomPicker ? Color.orange.opacity(0.2) : Color.white.opacity(0.07))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(showCustomPicker ? Color.orange.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Custom Duration Expansion Panel
            if showCustomPicker {
                customDurationPanel
            }

            // Error notice if assertion failed
            if let err = manager.lastErrorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                    Text(err)
                        .font(.system(size: 10))
                        .foregroundColor(.red.opacity(0.9))
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Custom Duration Input

    private var customDurationPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Hours Input
                HStack(spacing: 4) {
                    Stepper(value: $customHours, in: 0...24) {
                        Text("\(customHours)h")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }

                // Minutes Input
                HStack(spacing: 4) {
                    Stepper(value: $customMinutes, in: 0...59, step: 5) {
                        Text("\(customMinutes)m")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }

                Spacer()

                // Apply Button
                Button {
                    applyCustomDuration()
                } label: {
                    Text("Start")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(Color.orange)
                        )
                }
                .buttonStyle(.plain)
            }

            if let err = customError {
                Text(err)
                    .font(.system(size: 9.5))
                    .foregroundColor(.red.opacity(0.9))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private func applyCustomDuration() {
        switch KeepAwakeDuration.validate(hours: customHours, minutes: customMinutes) {
        case .success(let seconds):
            customError = nil
            manager.start(mode: manager.mode, duration: .custom(seconds))
            showCustomPicker = false
        case .failure(let err):
            customError = err.localizedDescription
        }
    }

    // MARK: - Clamshell Notice Footer

    private var clamshellNoticeFooter: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 10))
                .foregroundColor(Color.white.opacity(0.4))
                .padding(.top, 1)

            Text("MacBooks require AC power and an external display to stay awake with lid closed (macOS clamshell requirement).")
                .font(.system(size: 9))
                .foregroundColor(Color.white.opacity(0.45))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }
}
