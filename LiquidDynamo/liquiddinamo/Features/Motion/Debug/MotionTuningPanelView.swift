//
//  MotionTuningPanelView.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

#if DEBUG
import SwiftUI

/// Live motion tuning panel for interactive inspection of springs, content delays,
/// blur and scale amounts, and slow-motion frame-by-frame analysis.
public struct MotionTuningPanelView: View {
    @ObservedObject private var motion = IslandMotion.shared
    @ObservedObject private var controller = IslandController.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerView
                Divider()

                playbackSection
                Divider()

                stateSwitcherSection
                Divider()

                activitiesSection
                Divider()

                expandSpringSection
                collapseSpringSection
                alertSpringSection
                dropAnimationSection
                Divider()

                simulatorSection
                Divider()

                contentOutSection
                contentInSection
                Divider()

                interactionDelaysSection
                Divider()

                resetSection
            }
            .padding(18)
        }
        .frame(width: 440, height: 680)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dynamic Island Motion Tuner")
                    .font(.headline)
                Text("Inspect transitions, spring responses, damping, and blur in real-time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(Color.accentColor)
                .frame(width: 10, height: 10)
        }
    }

    // MARK: - Slow Motion & Accessibility

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Playback & Accessibility")
                .font(.subheadline)
                .bold()

            HStack {
                Text("Slow Motion:")
                    .font(.caption)
                Spacer()
                Picker("", selection: $motion.speedMultiplier) {
                    Text("1.0x (Normal)").tag(1.0)
                    Text("0.5x (2x Slow)").tag(0.5)
                    Text("0.25x (4x Slow)").tag(0.25)
                    Text("0.1x (10x Slow)").tag(0.1)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }

            Toggle("Force Reduce Motion (0.2s linear fade, no overshoot)", isOn: $motion.isReduceMotionForced)
                .font(.caption)
        }
    }

    // MARK: - State Switcher Preview

    private var stateSwitcherSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Live State Preview")
                    .font(.subheadline)
                    .bold()
                Spacer()
                Text("Current: \(String(describing: controller.state))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("Idle") {
                    controller.setIdle()
                }
                .buttonStyle(.borderedProminent)
                .tint(controller.state == .idle ? .blue : .secondary)

                Button("Compact") {
                    controller.setCompact()
                }
                .buttonStyle(.borderedProminent)
                .tint(controller.state == .compact ? .blue : .secondary)

                Button("Minimal") {
                    controller.setMinimal()
                }
                .buttonStyle(.borderedProminent)
                .tint(controller.state == .minimal ? .blue : .secondary)

                Button("Expanded") {
                    controller.setExpanded()
                }
                .buttonStyle(.borderedProminent)
                .tint(controller.state == .expanded ? .blue : .secondary)

                Button("Alert Pop") {
                    controller.showAlert(
                        payload: AlertPayload(
                            kind: .deviceConnected(name: "AirPods Pro", icon: "airpodspro"),
                            title: "AirPods Pro",
                            subtitle: "Connected • 95%",
                            iconName: "airpodspro",
                            iconColor: .white,
                            dwellDuration: motion.alertDwellDuration
                        )
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(controller.state == .alertPop ? .orange : .secondary)
            }
        }
    }

    // MARK: - Multi-Activity & Gooey Canvas Testing

    private var activitiesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Live Activities & Gooey Canvas")
                    .font(.subheadline)
                    .bold()
                Spacer()
                Text("Active: \(controller.registeredActivities.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("+ Timer") {
                    controller.registerActivity(IslandActivity(
                        id: "test.timer",
                        kind: .timer,
                        priority: 75,
                        leadingIcon: "timer",
                        title: "14:59",
                        tintColor: .orange
                    ))
                }
                .buttonStyle(.bordered)

                Button("- Timer") {
                    controller.removeActivity(id: "test.timer")
                }
                .buttonStyle(.bordered)

                Button("+ Call (High Pri)") {
                    controller.registerActivity(IslandActivity(
                        id: "test.call",
                        kind: .custom("Call"),
                        priority: 100,
                        leadingIcon: "phone.fill",
                        title: "Ongoing Call",
                        tintColor: .green
                    ))
                }
                .buttonStyle(.bordered)

                Button("- Call") {
                    controller.removeActivity(id: "test.call")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button("Split Bubble (Gooey)") {
                    controller.startGooeySplit()
                }
                .buttonStyle(.bordered)

                Button("Merge Bubble (Gooey)") {
                    controller.startGooeyMerge()
                }
                .buttonStyle(.bordered)

                Button("Clear Custom") {
                    controller.clearCustomActivities()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Expand Spring

    private var expandSpringSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Expand Spring (Width/Height Grow)")
                .font(.subheadline)
                .bold()

            sliderRow(
                label: "Response",
                value: $motion.expandResponse,
                range: 0.1...1.0,
                format: "%.2f s"
            )
            sliderRow(
                label: "Damping",
                value: $motion.expandDamping,
                range: 0.3...1.0,
                format: "%.2f"
            )
        }
    }

    // MARK: - Collapse Spring

    private var collapseSpringSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Collapse Spring (Both Dimensions Shrink)")
                .font(.subheadline)
                .bold()

            sliderRow(
                label: "Response",
                value: $motion.collapseResponse,
                range: 0.1...1.0,
                format: "%.2f s"
            )
            sliderRow(
                label: "Damping",
                value: $motion.collapseDamping,
                range: 0.3...1.0,
                format: "%.2f"
            )
            sliderRow(
                label: "Collapse Delay",
                value: $motion.collapseDelay,
                range: 0.00...0.30,
                format: "%.2f s"
            )
        }
    }

    // MARK: - Alert Spring

    private var alertSpringSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Alert Pop Spring (Punchy Overshoot)")
                .font(.subheadline)
                .bold()

            sliderRow(
                label: "Response",
                value: $motion.alertPopResponse,
                range: 0.1...1.0,
                format: "%.2f s"
            )
            sliderRow(
                label: "Damping",
                value: $motion.alertPopDamping,
                range: 0.3...1.0,
                format: "%.2f"
            )
        }
    }

    // MARK: - Liquid Glass Drop Timing & Dynamics

    private var dropAnimationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Liquid Glass Drop (Alerts & Popups)")
                .font(.subheadline)
                .bold()

            sliderRow(
                label: "1. Anticipation",
                value: $motion.dropAnticipationDuration,
                range: 0.05...0.30,
                format: "%.2f s"
            )
            sliderRow(
                label: "2. Birth",
                value: $motion.dropBirthDuration,
                range: 0.05...0.40,
                format: "%.2f s"
            )
            sliderRow(
                label: "3. Release",
                value: $motion.dropReleaseDuration,
                range: 0.05...0.30,
                format: "%.2f s"
            )
            sliderRow(
                label: "Squash Spring Response",
                value: $motion.dropSquashResponse,
                range: 0.10...0.80,
                format: "%.2f s"
            )
            sliderRow(
                label: "Squash Damping",
                value: $motion.dropSquashDamping,
                range: 0.30...1.00,
                format: "%.2f"
            )
            sliderRow(
                label: "Droplet Spacing (Neck)",
                value: $motion.dropSpacing,
                range: 20...60,
                format: "%.0f pt"
            )
            sliderRow(
                label: "Fall Vertical Stretch",
                value: $motion.dropStretchY,
                range: 1.0...1.6,
                format: "%.2fx"
            )
        }
    }

    // MARK: - Live Activity Simulator

    private var simulatorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Live Activity Simulator")
                .font(.subheadline)
                .bold()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                Button("Volume Sweep (Coalesce)") {
                    LiveActivitySimulator.shared.fireRapidVolumeSweep()
                }
                .buttonStyle(.bordered)

                Button("Output Device (AirPods)") {
                    LiveActivitySimulator.shared.fireAudioOutputDeviceChange()
                }
                .buttonStyle(.bordered)

                Button("Display Brightness HUD") {
                    LiveActivitySimulator.shared.fireDisplayBrightness()
                }
                .buttonStyle(.bordered)

                Button("Keyboard Backlight HUD") {
                    LiveActivitySimulator.shared.fireKeyboardBacklight()
                }
                .buttonStyle(.bordered)

                Button("Mic In-Use (Zoom)") {
                    LiveActivitySimulator.shared.fireMicrophoneInUse(appName: "Zoom")
                }
                .buttonStyle(.bordered)

                Button("Mic Mute Toggle") {
                    LiveActivitySimulator.shared.fireMicrophoneMute(isMuted: true)
                }
                .buttonStyle(.bordered)

                Button("Camera In-Use (FaceTime)") {
                    LiveActivitySimulator.shared.fireCameraInUse(appName: "FaceTime")
                }
                .buttonStyle(.bordered)

                Button("Power Connected") {
                    LiveActivitySimulator.shared.firePowerPluggedIn()
                }
                .buttonStyle(.bordered)

                Button("Low Battery (15%)") {
                    LiveActivitySimulator.shared.fireLowBattery15()
                }
                .buttonStyle(.bordered)

                Button("Critical Battery (5%)") {
                    LiveActivitySimulator.shared.fireCriticalBattery5()
                }
                .buttonStyle(.bordered)

                Button("Caps Lock Toggle") {
                    LiveActivitySimulator.shared.fireCapsLockToggle(isOn: true)
                }
                .buttonStyle(.bordered)

                Button("Pomodoro Focus Ring") {
                    LiveActivitySimulator.shared.firePomodoroSession()
                }
                .buttonStyle(.bordered)

                Button("Upcoming Calendar Event") {
                    LiveActivitySimulator.shared.fireUpcomingCalendarEvent()
                }
                .buttonStyle(.bordered)

                Button("Network Connected") {
                    LiveActivitySimulator.shared.fireNetworkConnected()
                }
                .buttonStyle(.bordered)

                Button("Network Disconnected") {
                    LiveActivitySimulator.shared.fireNetworkDisconnected()
                }
                .buttonStyle(.bordered)

                Button("VPN Connected (utun)") {
                    LiveActivitySimulator.shared.fireVPNConnected()
                }
                .buttonStyle(.bordered)

                Button("Focus Mode Toggle") {
                    LiveActivitySimulator.shared.fireFocusModeToggle(isOn: true)
                }
                .buttonStyle(.bordered)

                Button("Two Alerts At Once") {
                    LiveActivitySimulator.shared.fireTwoAlertsAtOnce()
                }
                .buttonStyle(.bordered)

                Button("Long Notification") {
                    LiveActivitySimulator.shared.fireLongNotification()
                }
                .buttonStyle(.bordered)

                Button("Progress Download") {
                    LiveActivitySimulator.shared.fireProgressDownload()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Content Out (Phase 1)

    private var contentOutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Phase 1: Content Out (Exit)")
                .font(.subheadline)
                .bold()

            sliderRow(
                label: "Duration",
                value: $motion.contentOutDuration,
                range: 0.05...0.40,
                format: "%.2f s"
            )
            sliderRow(
                label: "Blur Radius",
                value: $motion.contentOutBlur,
                range: 0...25,
                format: "%.0f pt"
            )
            sliderRow(
                label: "Exit Scale",
                value: $motion.contentOutScale,
                range: 0.80...1.00,
                format: "%.2f"
            )
        }
    }

    // MARK: - Content In (Phase 3)

    private var contentInSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Phase 3: Content In (Entry)")
                .font(.subheadline)
                .bold()

            sliderRow(
                label: "Stagger Delay",
                value: $motion.contentInDelay,
                range: 0.00...0.30,
                format: "%.2f s"
            )
            sliderRow(
                label: "Duration",
                value: $motion.contentInDuration,
                range: 0.10...0.60,
                format: "%.2f s"
            )
            sliderRow(
                label: "Initial Blur",
                value: $motion.contentInBlur,
                range: 0...25,
                format: "%.0f pt"
            )
            sliderRow(
                label: "Initial Scale",
                value: $motion.contentInScale,
                range: 0.80...1.00,
                format: "%.2f"
            )
        }
    }

    // MARK: - Interaction Delays

    private var interactionDelaysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hover & Dwell Delays")
                .font(.subheadline)
                .bold()

            sliderRow(
                label: "Hover Open Delay",
                value: $motion.hoverOpenDelay,
                range: 0.00...0.40,
                format: "%.2f s"
            )
            sliderRow(
                label: "Hover Close Grace",
                value: $motion.hoverCloseGrace,
                range: 0.05...0.60,
                format: "%.2f s"
            )
            sliderRow(
                label: "Alert Dwell Duration",
                value: $motion.alertDwellDuration,
                range: 1.0...8.0,
                format: "%.1f s"
            )
        }
    }

    // MARK: - Reset

    private var resetSection: some View {
        HStack {
            Spacer()
            Button("Reset All Parameters to Default") {
                withAnimation {
                    motion.resetToDefaults()
                }
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: - Helper Slider Row

    private func sliderRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String
    ) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 130, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: format, value.wrappedValue))
                .font(.caption.monospacedDigit())
                .frame(width: 60, alignment: .trailing)
        }
    }
}
#endif
