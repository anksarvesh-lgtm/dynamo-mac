//
//  LiveActivityTemplates.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import Combine
import Defaults
import Foundation
import SwiftUI

// MARK: - 1. HUD Template (Volume, Brightness, Backlight)

public struct LiveActivityHUDView: View {
    public let activity: LiveActivity
    @ObservedObject private var hub = LiveActivityCenter.shared
    @State private var dragProgress: Double? = nil

    public init(activity: LiveActivity) {
        self.activity = activity
    }

    private var currentLevel: Double {
        dragProgress ?? (activity.payload.value ?? 0.5)
    }

    public var body: some View {
        HStack(spacing: 12) {
            // HUD Icon
            if let icon = activity.payload.iconName {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22)
            }

            // Interactive Slider or Level Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 8)

                    // Fill
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [activity.tint, activity.tint.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, geo.size.width * CGFloat(min(max(currentLevel, 0.0), 1.0))), height: 8)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            hub.isDraggingSlider = true
                            let progress = min(max(value.location.x / geo.size.width, 0.0), 1.0)
                            dragProgress = progress
                            // Notify caller/manager
                            if let action = activity.payload.action {
                                action()
                            }
                        }
                        .onEnded { _ in
                            hub.isDraggingSlider = false
                            dragProgress = nil
                        }
                )
            }
            .frame(height: 18)

            // Percentage label
            Text("\(Int(currentLevel * 100))%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.3), radius: 6, y: 2)
    }
}

// MARK: - 2. Ongoing Compact Wings Template (Music, Timer, Call, Recording)

public struct LiveActivityCompactWingView: View {
    public let activity: LiveActivity
    public let isLeading: Bool

    public init(activity: LiveActivity, isLeading: Bool) {
        self.activity = activity
        self.isLeading = isLeading
    }

    public var body: some View {
        HStack(spacing: 6) {
            if isLeading {
                if let icon = activity.payload.iconName {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(activity.tint)
                }
                Text(activity.payload.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            } else {
                if let subtitle = activity.payload.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                }
                if let icon = activity.payload.iconName {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(activity.tint)
                }
            }
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - 3. Progress Template (Ring or Horizontal Bar)

public struct LiveActivityProgressView: View {
    public let activity: LiveActivity

    public init(activity: LiveActivity) {
        self.activity = activity
    }

    private var progressValue: Double {
        activity.payload.value ?? 0.0
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Ring or Bar
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 3.5)
                    .frame(width: 26, height: 26)

                Circle()
                    .trim(from: 0.0, to: CGFloat(progressValue))
                    .stroke(activity.tint, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .frame(width: 26, height: 26)
                    .rotationEffect(.degrees(-90))

                if let icon = activity.payload.iconName {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(activity.tint)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.payload.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let subtitle = activity.payload.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text("\(Int(progressValue * 100))%")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(activity.tint)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule().strokeBorder(activity.tint.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - 4. Notification Card Template

public struct LiveActivityNotificationCardView: View {
    public let activity: LiveActivity
    public var onDismiss: () -> Void = {}
    @State private var dragOffset: CGFloat = 0.0

    public init(activity: LiveActivity, onDismiss: @escaping () -> Void = {}) {
        self.activity = activity
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // App Icon
            if let icon = activity.payload.iconName {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(activity.tint)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(activity.tint.opacity(0.18))
                    )
            }

            // Title + Body (up to 2 lines)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(activity.payload.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Text("now")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                if let body = activity.payload.body {
                    Text(body)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Optional Action Button
                if let actionTitle = activity.payload.actionTitle {
                    Button(action: {
                        activity.payload.action?()
                        onDismiss()
                    }) {
                        Text(actionTitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(activity.tint.opacity(0.8))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
        }
        .padding(14)
        .frame(width: 330)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.35), radius: 8, y: 4)
        .offset(y: dragOffset)
        .avoidsNotch(id: "NotificationCard:\(activity.id)")
        .onHover { hovering in
            LiveActivityCenter.shared.isHovering = hovering
        }
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    // Only allow upward dragging for dismiss flick
                    if gesture.translation.height < 0 {
                        dragOffset = gesture.translation.height
                    }
                }
                .onEnded { gesture in
                    if gesture.translation.height < -20 || gesture.velocity.height < -100 {
                        // Flick / swipe up to dismiss
                        withAnimation(IslandMotion.shared.collapseSpring) {
                            dragOffset = -100
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            onDismiss()
                        }
                    } else {
                        // Snap back
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .onTapGesture {
            activity.payload.action?()
        }
    }
}

// MARK: - 5. Expanded Details View

public struct LiveActivityExpandedDetailsView: View {
    public let activity: LiveActivity
    public var onClose: () -> Void = {}

    public init(activity: LiveActivity, onClose: @escaping () -> Void = {}) {
        self.activity = activity
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if let icon = activity.payload.iconName {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(activity.tint)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(activity.tint.opacity(0.2)))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.payload.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)

                    if let subtitle = activity.payload.subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if let body = activity.payload.body {
                Text(body)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
            }

            // Interactive Action Buttons
            HStack(spacing: 10) {
                if let actionTitle = activity.payload.actionTitle {
                    Button(action: {
                        activity.payload.action?()
                        onClose()
                    }) {
                        Text(actionTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(activity.tint))
                    }
                    .buttonStyle(.plain)
                }

                if let secTitle = activity.payload.secondaryActionTitle {
                    Button(action: {
                        activity.payload.secondaryAction?()
                        onClose()
                    }) {
                        Text(secTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
    }
}
