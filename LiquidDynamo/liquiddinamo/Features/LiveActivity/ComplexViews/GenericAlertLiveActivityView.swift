//
//  GenericAlertLiveActivityView.swift
//  LiquidDynamo
//
//  Step 4: Unified Liquid Island Engine generic alert view.
//  Replaces rigid capsule LiquidDropAlertView with continuous auto-sizing liquid container.
//

import AppKit
import Foundation
import SwiftUI

public struct GenericAlertLiveActivityView: View {
    public let activity: LiveActivity
    public var onDismiss: () -> Void = {}

    public init(activity: LiveActivity, onDismiss: @escaping () -> Void = {}) {
        self.activity = activity
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Icon Badge
            let iconName = activity.payload.iconName ?? "bell.fill"
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(activity.payload.iconColor ?? activity.tint)
                .frame(width: 26, height: 26)
                .background(
                    Circle().fill((activity.payload.iconColor ?? activity.tint).opacity(0.18))
                )

            // Title & Subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.payload.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let subtitle = activity.payload.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            // Optional percentage / battery or progress value
            if let val = activity.payload.value {
                Text("\(Int(val * 100))%")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(activity.tint)
            }

            // Dismiss Button
            Button(action: {
                onDismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .avoidsNotch(id: "GenericAlert:\(activity.id)")
    }
}
