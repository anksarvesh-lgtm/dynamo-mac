//
//  TimerLiveActivityView.swift
//  LiquidDynamo
//
//  Step 3 Complex View Migration: Timers & Pomodoro Sessions.
//  Provides both compact top band wing presentation and organic below-notch blooming droplet presentation.
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

public struct TimerLiveActivityView: View {
    @ObservedObject var timerSource = TimerActivitySource.shared
    @ObservedObject var motion = IslandMotion.shared

    public var isCompactWing: Bool = false
    public var isLeadingWing: Bool = true
    public var onDismiss: () -> Void = {}

    public init(
        isCompactWing: Bool = false,
        isLeadingWing: Bool = true,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.isCompactWing = isCompactWing
        self.isLeadingWing = isLeadingWing
        self.onDismiss = onDismiss
    }

    private var progress: Double {
        guard timerSource.totalDuration > 0 else { return 0.0 }
        let elapsed = timerSource.totalDuration - timerSource.remainingSeconds
        return min(max(elapsed / timerSource.totalDuration, 0.0), 1.0)
    }

    private var tintColor: Color {
        Color.orange
    }

    private var formattedTime: String {
        let total = Int(max(0, timerSource.remainingSeconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    public var body: some View {
        if isCompactWing {
            compactWingLayout
        } else {
            bloomingDropletLayout
        }
    }

    // MARK: - 1. Compact Wing Presentation (Top Band)

    private var compactWingLayout: some View {
        HStack(spacing: 5) {
            if isLeadingWing {
                Image(systemName: timerSource.sessionType.iconName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tintColor)
                Text(timerSource.sessionType.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            } else {
                Text(formattedTime)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                Image(systemName: "timer")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tintColor)
            }
        }
        .padding(.horizontal, 6)
        .avoidsNotch(id: isLeadingWing ? "TimerWingL" : "TimerWingR")
    }

    // MARK: - 2. Blooming Droplet Presentation (Below Notch)

    private var bloomingDropletLayout: some View {
        HStack(spacing: 14) {
            // Circular Countdown Progress Ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 3.5)
                    .frame(width: 32, height: 32)

                Circle()
                    .trim(from: 0.0, to: CGFloat(1.0 - progress))
                    .stroke(
                        tintColor,
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
                    .frame(width: 32, height: 32)
                    .rotationEffect(.degrees(-90))

                Image(systemName: timerSource.sessionType.iconName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tintColor)
            }

            // Session Title & Remaining Time
            VStack(alignment: .leading, spacing: 2) {
                Text(timerSource.sessionType.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(formattedTime)
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(tintColor)
            }

            Spacer(minLength: 8)

            // Pause / Resume Quick Action Button
            Button(action: {
                if timerSource.isPaused {
                    timerSource.resumeTimer()
                } else {
                    timerSource.pauseTimer()
                }
                triggerHaptic()
            }) {
                Image(systemName: timerSource.isPaused ? "play.circle.fill" : "pause.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(tintColor)
            }
            .buttonStyle(.plain)

            // Cancel / Dismiss Button
            Button(action: {
                timerSource.stopTimer()
                triggerHaptic()
                onDismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .avoidsNotch(id: "TimerBloomingDroplet")
    }

    private func triggerHaptic() {
        if Defaults[.enableHaptics] {
            NSHapticFeedbackManager.defaultPerformer.perform(
                .alignment,
                performanceTime: .default
            )
        }
    }
}
