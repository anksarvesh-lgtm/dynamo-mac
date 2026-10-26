//
//  WatcherPillView.swift
//  LiquidDynamo
//
//  Created for LiquidDynamo Watcher (AI Agent & Coding Session Monitor)
//

import AppKit
import Defaults
import SwiftUI

/// Compact 3D Liquid Glass pill displaying live AI agent sessions in LiquidDynamo's native UI style.
/// Positioned in the notch, wing, or dashboard without covering the workspace.
public struct WatcherPillView: View {
    @ObservedObject var watcher = WatcherService.shared
    @ObservedObject private var safeArea = NotchSafeAreaEngine.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var measuredContentWidth: CGFloat = 0
    @State private var isHovered: Bool = false

    public init() {}

    private var currentSession: WatcherSession? {
        watcher.primarySession
    }

    private var accentColor: Color {
        currentSession?.agentKind.themeColor ?? .accentColor
    }

    private var capsuleDimensions: (width: CGFloat, height: CGFloat) {
        let geom = safeArea.currentGeometry
        let minW: CGFloat = geom.hasPhysicalNotch ? max(200.0, geom.rawNotchWidth) : 200.0
        let maxW: CGFloat = min(460.0, max(300.0, geom.screenFrame.width * 0.45))
        let effectiveMeasuredW = measuredContentWidth > 0 ? (measuredContentWidth + 24.0) : (IslandController.shared.dynamicAlertCapsuleWidth ?? 220.0)
        let finalWidth = min(maxW, max(minW, effectiveMeasuredW))
        let finalHeight = max(38.0, min(46.0, max(geom.notchHeight, 38.0)))
        return (finalWidth, finalHeight)
    }

    public var body: some View {
        if let session = currentSession {
            let dims = capsuleDimensions

            ZStack {
                compactHorizontalContent(session: session)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: EventCapsuleIntrinsicWidthPreferenceKey.self, value: geo.size.width)
                        }
                    )
                    .hidden()

                compactHorizontalContent(session: session)
                    .frame(width: max(0, dims.width - 24.0))
            }
            .onPreferenceChange(EventCapsuleIntrinsicWidthPreferenceKey.self) { newWidth in
                if newWidth > 0 && abs(newWidth - measuredContentWidth) > 1.0 {
                    measuredContentWidth = newWidth
                    let geom = safeArea.currentGeometry
                    let minW: CGFloat = geom.hasPhysicalNotch ? max(200.0, geom.rawNotchWidth) : 200.0
                    let maxW: CGFloat = min(460.0, max(300.0, geom.screenFrame.width * 0.45))
                    let calculated = min(maxW, max(minW, newWidth + 24.0))
                    IslandController.shared.reportAlertCapsuleWidth(calculated)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(width: dims.width, height: dims.height)
                .background(
                    ZStack {
                        LiquidGlassSurface(
                            shape: Capsule(),
                            isNotchAnchored: false,
                            ambientColor: accentColor,
                            scrimFloor: 0.35
                        )
                        // 3D Glass Specular Sheen Highlight
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.35),
                                        Color.white.opacity(0.12),
                                        Color.white.opacity(0.02)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.8
                            )
                    }
                )
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.40), radius: 8, y: 3)
                .avoidsNotch(id: "WatcherPill")
                .contentShape(Capsule())
                .scaleEffect(isHovered && !reduceMotion ? 1.02 : 1.0)
                .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isHovered)
                .onHover { h in isHovered = h }
                .onTapGesture {
                    watcher.isExpandedCardOpen.toggle()
                }
        }
    }

    // MARK: - Minimal Horizontal Layout

    @ViewBuilder
    private func compactHorizontalContent(session: WatcherSession) -> some View {
        HStack(spacing: 8) {
            // Agent Icon with live pulse indicator
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: session.agentKind.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(session.agentKind.themeColor)
                    .frame(width: 20, height: 20)

                // State indicator dot
                Circle()
                    .fill(stateColor(session.state))
                    .frame(width: 5, height: 5)
                    .offset(x: 2, y: 2)
            }

            // Agent Name
            Text(session.displayName)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            // Dot Separator
            Text("•")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.35))

            // Live State / Action
            sessionStatusView(session: session)
        }
    }

    @ViewBuilder
    private func sessionStatusView(session: WatcherSession) -> some View {
        switch session.state {
        case .idle:
            Text("Idle")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))

        case .thinking:
            HStack(spacing: 4) {
                Text("Thinking")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))

                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
            }

        case .working(let tool):
            HStack(spacing: 4) {
                Text(tool)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.accentColor.opacity(0.95))
                    .lineLimit(1)

                if let diff = session.diffSummary {
                    Text(diff.formattedSummary)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(diff.additions > 0 ? Color.green : Color.red)
                }
            }

        case .permissionRequested:
            HStack(spacing: 5) {
                Button(action: {
                    watcher.respondToPermission(sessionId: session.id, allow: true)
                }) {
                    Text("Allow")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.green.opacity(0.3))
                        .clipShape(Capsule())
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)

                Button(action: {
                    watcher.respondToPermission(sessionId: session.id, allow: false)
                }) {
                    Text("Deny")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.red.opacity(0.25))
                        .clipShape(Capsule())
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

        case .finished:
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.green)

                Text("Done")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.green)
            }

        case .error:
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.red)

                Text("Error")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.red)
            }
        }
    }

    private func stateColor(_ state: WatcherSessionState) -> Color {
        switch state {
        case .idle: return .secondary
        case .thinking: return .cyan
        case .working: return .green
        case .permissionRequested: return .orange
        case .finished: return .green
        case .error: return .red
        }
    }
}
