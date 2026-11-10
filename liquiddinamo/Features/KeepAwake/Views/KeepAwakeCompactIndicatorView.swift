//
//  KeepAwakeCompactIndicatorView.swift
//  LiquidDynamo
//
//  Compact Dynamic Island indicator for active Keep Awake sessions.
//  Displays a subtle cup/shield icon and remaining time without crowding media or calls.
//

import SwiftUI

public struct KeepAwakeCompactIndicatorView: View {
    @ObservedObject private var manager = KeepAwakeManager.shared
    @State private var isHovering: Bool = false

    public init() {}

    public var body: some View {
        guard manager.isActive else {
            return AnyView(EmptyView())
        }

        return AnyView(
            HStack(spacing: 4) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Color.orange)

                if isHovering || manager.isIndefinite {
                    Text(manager.isIndefinite ? "∞" : manager.formatTimeIntervalShort(manager.remainingSeconds))
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    Text(manager.formatTimeIntervalShort(manager.remainingSeconds))
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(
                Capsule().fill(Color.orange.opacity(0.15))
            )
            .overlay(
                Capsule().stroke(Color.orange.opacity(0.35), lineWidth: 0.8)
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
            .help(
                manager.isIndefinite
                    ? "Keep Awake active (Indefinite - \(manager.mode.shortTitle))"
                    : "Keep Awake active (\(manager.remainingFormatted) remaining - \(manager.mode.shortTitle))"
            )
        )
    }
}
