//
//  WatcherDetailCard.swift
//  LiquidDynamo
//
//  Created for LiquidDynamo Watcher (AI Agent & Coding Session Monitor)
//

import AppKit
import Defaults
import SwiftUI

/// Detailed Liquid Glass card for expanded AI agent session inspection.
/// Bounded to max 360pt width matching LiquidDynamo compact layout standards.
public struct WatcherDetailCard: View {
    @ObservedObject var watcher = WatcherService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        if let session = watcher.primarySession {
            sessionCard(session: session)
        } else {
            idleCard
        }
    }

    @ViewBuilder
    private func sessionCard(session: WatcherSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow(session: session)

            if let prompt = session.prompt, !prompt.isEmpty {
                Text(prompt)
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .padding(7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.06))
                    )
            }

            toolsRow(session: session)

            if let stepTitle = session.stepTitle, let sIdx = session.stepIndex, let sTot = session.stepTotal {
                stepProgressView(session: session, stepTitle: stepTitle, index: sIdx, total: sTot)
            }

            if session.accountInfo != nil || session.keepAwakeInfo != nil || session.tokenInfo != nil {
                contextBadgesView(session: session)
            }

            if case .permissionRequested(_, let details) = session.state {
                permissionView(session: session, details: details)
            }
        }
        .padding(12)
        .frame(maxWidth: 360)
        .liquidGlass(preset: .studioLiquid, cornerRadius: 16)
    }

    @ViewBuilder
    private func headerRow(session: WatcherSession) -> some View {
        HStack(spacing: 8) {
            Image(systemName: session.agentKind.iconName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(session.agentKind.themeColor)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(session.agentKind.themeColor.opacity(0.18))
                        .overlay(Circle().stroke(session.agentKind.themeColor.opacity(0.4), lineWidth: 0.75))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(session.displayName)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("AI Coding Agent Session")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            Text(session.state.statusLabel)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(
                    Capsule()
                        .fill(session.state.isActionable ? Color.orange.opacity(0.25) : Color.white.opacity(0.12))
                )
                .foregroundStyle(session.state.isActionable ? Color.orange : Color.white.opacity(0.85))
        }
    }

    @ViewBuilder
    private func toolsRow(session: WatcherSession) -> some View {
        HStack(spacing: 8) {
            if let tool = session.activeTool {
                HStack(spacing: 4) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(tool)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                }
            }

            Spacer()

            if let diff = session.diffSummary {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(diff.fileName)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                    Text(diff.formattedSummary)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(diff.additions > 0 ? Color.green : Color.red)
                }
            }
        }
    }

    @ViewBuilder
    private func stepProgressView(session: WatcherSession, stepTitle: String, index: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet.clipboard.fill")
                        .font(.system(size: 8.5))
                        .foregroundStyle(session.agentKind.themeColor)
                    Text("Step \(index) of \(total)")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(session.agentKind.themeColor)
                }

                Spacer()

                if let prog = session.progress {
                    Text("\(Int(prog * 100))%")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            Text(stepTitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(2)

            if let prog = session.progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(session.agentKind.themeColor)
                            .frame(width: max(4, geo.size.width * CGFloat(min(1.0, max(0.0, prog)))))
                    }
                }
                .frame(height: 3.5)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.white.opacity(0.06))
        )
    }

    @ViewBuilder
    private func contextBadgesView(session: WatcherSession) -> some View {
        HStack(spacing: 6) {
            if let acc = session.accountInfo {
                HStack(spacing: 3) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 8))
                    Text(acc)
                        .font(.system(size: 8.5, weight: .medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Capsule().fill(Color.blue.opacity(0.2)))
                .foregroundStyle(Color.blue.opacity(0.9))
            }

            if let awake = session.keepAwakeInfo {
                HStack(spacing: 3) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 8))
                    Text(awake)
                        .font(.system(size: 8.5, weight: .medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Capsule().fill(Color.orange.opacity(0.2)))
                .foregroundStyle(Color.orange.opacity(0.9))
            }

            if let tok = session.tokenInfo {
                HStack(spacing: 3) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 8))
                    Text(tok)
                        .font(.system(size: 8.5, weight: .medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Capsule().fill(Color.white.opacity(0.1)))
                .foregroundStyle(.white.opacity(0.8))
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func permissionView(session: WatcherSession, details: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(details)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.orange.opacity(0.95))
                .lineLimit(2)

            HStack(spacing: 8) {
                Button(action: {
                    watcher.respondToPermission(sessionId: session.id, allow: true)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("Allow")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.35))
                    .clipShape(Capsule())
                    .foregroundStyle(.green)
                }
                .buttonStyle(.plain)

                Button(action: {
                    watcher.respondToPermission(sessionId: session.id, allow: true, always: true)
                }) {
                    Text("Always")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button(action: {
                    watcher.respondToPermission(sessionId: session.id, allow: false)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("Deny")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.30))
                    .clipShape(Capsule())
                    .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.30), lineWidth: 0.75))
        )
    }

    private var idleCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Text("Watcher: No active agent sessions")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Simulate") {
                watcher.simulateAgentActivity()
            }
            .font(.system(size: 9, weight: .semibold))
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 360)
        .liquidGlass(preset: .studioLiquid, cornerRadius: 16)
    }
}
