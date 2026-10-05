//
//  HoverButton.swift
//  boringNotch
//
//  Created by Kraigo on 04.09.2024.
//

import SwiftUI

struct HoverButton: View {
    var icon: String
    var iconColor: Color = .primary
    var scale: Image.Scale = .medium
    var action: () -> Void
    var contentTransition: ContentTransition = .symbolEffect

    @State private var isHovering = false
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let size = CGFloat(scale == .large ? 38 : 30)
        let iconSize = CGFloat(scale == .large ? 22 : 16)

        Button(action: action) {
            ZStack {
                Capsule()
                    .fill(.ultraThinMaterial)

                Capsule()
                    .fill(Color.black.opacity(isPressed ? 0.35 : (isHovering ? 0.45 : 0.6)))

                if isHovering {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.2),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                Premium3DIconView(
                    name: icon,
                    size: iconSize,
                    isSelected: isHovering,
                    customTint: iconColor == .primary ? nil : iconColor,
                    interactive: false
                )
            }
            .frame(width: size, height: size)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isHovering ? 0.4 : 0.18),
                                Color.white.opacity(isHovering ? 0.15 : 0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            )
            .shadow(
                color: Color.black.opacity(isHovering ? 0.3 : 0.1),
                radius: isHovering ? 6 : 2,
                y: isHovering ? 3 : 1
            )
            .scaleEffect(isPressed ? 0.92 : (isHovering && !reduceMotion ? 1.06 : 1.0))
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovering)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovering = hovering
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}
