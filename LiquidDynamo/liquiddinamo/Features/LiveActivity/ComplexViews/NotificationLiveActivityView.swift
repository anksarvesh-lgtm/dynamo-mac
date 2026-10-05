//
//  NotificationLiveActivityView.swift
//  LiquidDynamo
//
//  Step 3 Complex View Migration: System & App Notification Cards.
//  Provides interactive notifications inside the auto-sizing liquid container.
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

public struct NotificationLiveActivityView: View {
    public let activity: LiveActivity
    public var onDismiss: () -> Void = {}

    public init(activity: LiveActivity, onDismiss: @escaping () -> Void = {}) {
        self.activity = activity
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // App Icon / Notification Badge
            if let icon = activity.payload.iconName {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(activity.tint)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(activity.tint.opacity(0.18))
                    )
            } else {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(activity.tint)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(activity.tint.opacity(0.18))
                    )
            }

            // Title + Body (up to 2 lines)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(activity.payload.title)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Text("now")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }

                if let body = activity.payload.body {
                    Text(body)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Action Buttons Row
                if activity.payload.actionTitle != nil || activity.payload.secondaryActionTitle != nil {
                    HStack(spacing: 8) {
                        if let actionTitle = activity.payload.actionTitle {
                            Button(action: {
                                activity.payload.action?()
                                onDismiss()
                            }) {
                                Text(actionTitle)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 3.5)
                                    .background(
                                        Capsule().fill(activity.tint.opacity(0.85))
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        if let secTitle = activity.payload.secondaryActionTitle {
                            Button(action: {
                                activity.payload.secondaryAction?()
                                onDismiss()
                            }) {
                                Text(secTitle)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3.5)
                                    .background(
                                        Capsule().fill(Color.white.opacity(0.12))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 3)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 320)
        .avoidsNotch(id: "NotificationLiveActivity:\(activity.id)")
        .onTapGesture {
            activity.payload.action?()
        }
    }
}
